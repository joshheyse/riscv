
`timescale 1ns / 1ps

// Pipelined instruction fetch unit.
//
// Contract:
// - `pc` is the next byte address to request.
// - Once issued, `ibus.req.valid` and its payload remain stable until the
//   instruction-side memory port accepts the request with `req_ready`.
// - The instruction-side memory port may return the response later with
//   `ibus.rsp.valid`.
// - `fetched` is a one-entry output buffer, not a one-cycle pulse. It stays
//   valid while the pipeline is stalled and clears when `fetch_en` says the
//   core can accept it.
//
// The IFU only tracks one outstanding request. On redirect, any older
// outstanding response belongs to the wrong path and must be ignored before
// issuing the redirected fetch.
//
module ifu
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic      clk,
  input logic      rst,
  input logic      fetch_en,
  input redirect_t redirect,

  output pc_t    pc,
  output if_id_t fetched,

  vmem_if.master ibus
);

  typedef enum logic [2:0] {
    IDLE,
    REQUEST,
    WAIT,
    DROP_REQUEST,
    DROP_WAIT
  } state_e;

  state_e _state;
  pc_t    _request_pc;
  logic   _request_transfer;
  logic   _response_transfer;
  trap_req_t _fetch_trap_req;

  always_comb begin
    ibus.req = '0;
    ibus.req.valid = (_state == REQUEST) || (_state == DROP_REQUEST);
    ibus.req.addr = _request_pc;

    // This master always has room for the one response it requested.
    ibus.rsp_ready = 1'b1;

    _request_transfer = ibus.req.valid && ibus.req_ready;
    _response_transfer = ibus.rsp.valid && ibus.rsp_ready;
  end

  mmu_trap_control _mmu_trap_control (
    .fault(ibus.rsp.fault),
    .access(MMU_ACCESS_FETCH),
    .virtual_addr(_request_pc),
    .trap_req(_fetch_trap_req)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      _state      <= IDLE;
      pc          <= '0;
      fetched     <= '0;
      _request_pc <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (redirect.valid) begin
            pc      <= redirect.pc;
            fetched <= '0;
          end else begin
            if (fetch_en && fetched.valid) begin
              fetched <= '0;
            end
            if (fetch_en) begin
              _request_pc <= pc;
              pc          <= pc + pc_t'(4);
              _state      <= REQUEST;
            end
          end
        end

        REQUEST: begin
          if (redirect.valid) begin
            pc      <= redirect.pc;
            fetched <= '0;
            if (_request_transfer && _response_transfer) begin
              _state <= IDLE;
            end else if (_request_transfer) begin
              _state <= DROP_WAIT;
            end else begin
              _state <= DROP_REQUEST;
            end
          end else if (_request_transfer && _response_transfer) begin
            fetched <= '{
              valid: 1'b1,
              slot: '{instr: ibus.rsp.read_data, pc: _request_pc},
              trap_req: _fetch_trap_req
            };
            _state <= IDLE;
          end else if (_request_transfer) begin
            _state <= WAIT;
          end
        end

        WAIT: begin
          if (redirect.valid) begin
            pc      <= redirect.pc;
            fetched <= '0;
            _state  <= _response_transfer ? IDLE : DROP_WAIT;
          end else if (_response_transfer) begin
            fetched <= '{
              valid: 1'b1,
              slot: '{instr: ibus.rsp.read_data, pc: _request_pc},
              trap_req: _fetch_trap_req
            };
            _state <= IDLE;
          end
        end

        DROP_REQUEST: begin
          if (redirect.valid) begin
            pc      <= redirect.pc;
            fetched <= '0;
          end
          if (_request_transfer && _response_transfer) begin
            _state <= IDLE;
          end else if (_request_transfer) begin
            _state <= DROP_WAIT;
          end
        end

        DROP_WAIT: begin
          if (redirect.valid) begin
            pc      <= redirect.pc;
            fetched <= '0;
          end
          if (_response_transfer) begin
            _state <= IDLE;
          end
        end

        default: begin
          _state <= IDLE;
        end
      endcase
    end
  end

endmodule
