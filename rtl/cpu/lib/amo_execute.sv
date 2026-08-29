`timescale 1ns / 1ps

// Serialized atomic-memory-operation engine.
//
// The decoded aq/rl bits are preserved in the latched request. The current
// in-order pipeline must hold younger memory instructions until this engine's
// response transfers. Because the core has no store buffer, speculative memory
// execution, or multiple outstanding data operations, that serialization is
// stronger than the acquire/release ordering requested by aq/rl. If the memory
// pipeline later gains overlap, those bits must drive explicit ordering logic.
module amo_execute
  import riscv_pkg::*;
(
  input  logic     clk,
  input  logic     rst,
  input  amo_req_t req,
  output logic     req_ready,

  output amo_rsp_t rsp,
  input  logic     rsp_ready,
  input  logic     reservation_clear,

  vmem_if.master memory
);

  typedef enum logic [2:0] {
    IDLE,
    AMO_READ_REQUEST,
    AMO_READ_WAIT,
    AMO_WRITE_REQUEST,
    AMO_WRITE_WAIT,
    RESPOND
  } state_t;

  state_t               _state;
  amo_req_t             _request;
  integer_data_t        _old_value;
  integer_data_t        _new_value;
  amo_rsp_t             _respond;
  logic                 _reservation_valid;
  logic          [29:0] _reservation_addr;

  amo_alu _alu (
    .op(_request.ctrl.op),
    .old_value(_old_value),
    .operand(_request.operand),
    .new_value(_new_value)
  );

  always_comb begin
    req_ready = (_state == IDLE);
    rsp = _respond;
    memory.req = '0;
    memory.rsp_ready = (_state == AMO_READ_WAIT || _state == AMO_WRITE_WAIT);

    case (_state)
      AMO_READ_REQUEST: begin
        memory.req = '{
            valid: 1'b1,
            addr: _request.address,
            write_en: 1'b0,
            write_data: '0,
            write_mask: '0
        };
      end
      AMO_WRITE_REQUEST: begin
        memory.req = '{
            valid: 1'b1,
            addr: _request.address,
            write_en: 1'b1,
            write_data: _new_value,
            write_mask: '1
        };
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _old_value <= '0;
      _request <= '0;
      _respond <= '0;
      _reservation_valid <= 1'b0;
      _reservation_addr <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (req.valid && req_ready) begin
            _state <= AMO_READ_REQUEST;
            _request <= req;
            _respond.valid <= 1'b0;
          end
        end
        AMO_READ_REQUEST: begin
          if (memory.req.valid && memory.req_ready) begin
            _state <= AMO_READ_WAIT;
          end
        end
        AMO_READ_WAIT: begin
          if (memory.rsp.valid && memory.rsp_ready) begin
            if (_request.ctrl.op != AMO_OP_LR) begin
              _reservation_valid <= 1'b0;
              _reservation_addr  <= '0;
            end
            if (memory.rsp.fault != MMU_FAULT_NONE) begin
              _respond <= '{valid: 1'b1, result: '0, fault: memory.rsp.fault};
              _state   <= RESPOND;
            end else begin
              _old_value <= memory.rsp.read_data;
              case (_request.ctrl.op)
                AMO_OP_LR: begin
                  _reservation_valid <= 1'b1;
                  _reservation_addr <= memory.rsp.physical_addr[31:2];
                  _respond <= '{
                      valid: 1'b1,
                      result: memory.rsp.read_data,
                      fault: MMU_FAULT_NONE
                  };
                  _state <= RESPOND;
                end
                AMO_OP_SC: begin
                  if(_reservation_valid && memory.rsp.physical_addr[31:2] == _reservation_addr) begin
                    _state <= AMO_WRITE_REQUEST;
                  end else begin
                    _respond <= '{valid: 1'b1, result: 32'b1, fault: MMU_FAULT_NONE};
                    _state   <= RESPOND;
                  end
                end
                default: begin
                  _state <= AMO_WRITE_REQUEST;
                end
              endcase
            end
          end
        end
        AMO_WRITE_REQUEST: begin
          if (memory.req.valid && memory.req_ready) begin
            _state <= AMO_WRITE_WAIT;
          end
        end
        AMO_WRITE_WAIT: begin
          if (memory.rsp.valid && memory.rsp_ready) begin
            _respond <= '{
                valid: 1'b1,
                result: (_request.ctrl.op == AMO_OP_SC ? '0 : _old_value),
                fault: memory.rsp.fault
            };
            _state <= RESPOND;
          end
        end
        RESPOND: begin
          if (rsp.valid && rsp_ready) begin
            _respond.valid <= 1'b0;
            _state <= IDLE;
          end
        end
      endcase
    end

    if (reservation_clear) begin
      _reservation_valid <= 1'b0;
      _reservation_addr  <= '0;
    end
  end

  // The executor accepts exactly one architectural AMO at a time and preserves
  // its complete decoded request, including aq/rl, until completion.
  a_no_second_request_accept :
  assert property (@(posedge clk) disable iff (rst) (_state != IDLE) |-> !(req.valid && req_ready))
  else $error("amo_execute: accepted a second request while active");

  a_latched_request_stable :
  assert property (@(posedge clk) disable iff (rst)
      (_state != IDLE && !((_state == RESPOND) && rsp.valid && rsp_ready))
      |=> $stable(
      _request
  ))
  else $error("amo_execute: latched request changed before completion");

endmodule
