`timescale 1ns / 1ps

module translation_adapter
  import riscv_pkg::*;
  import sv32_pkg::*;
(
  input logic clk,
  input logic rst,

  input satp_t satp,
  input translation_ctx_t ctx,

  vmem_if.slave    upstream,
  mmu_if.requester translation,
  mem_if.master    downstream
);

  typedef enum logic [2:0] {
    IDLE,
    BYPASS_WAIT,
    TRANSLATE_REQUEST,
    TRANSLATE_WAIT,
    PHYSICAL_REQUEST,
    PHYSICAL_WAIT,
    RESPOND
  } state_e;

  state_e _state;
  translation_ctx_t _ctx;
  mmu_req_t _mmu_request;
  // verilator lint_off UNUSEDSIGNAL
  vmem_req_t _vmem_request;
  // verilator lint_on UNUSEDSIGNAL
  vmem_rsp_t _vmem_response;
  mem_addr_t _physical_addr;
  mem_req_t _mem_request;

  always_comb begin
    upstream.rsp = _vmem_response;
    upstream.req_ready = (_state == IDLE) &&
        (!translation_bypassed(satp, ctx) || downstream.req_ready);
    translation.req = _mmu_request;
    translation.rsp_ready = (_state == TRANSLATE_WAIT);
    downstream.req = _mem_request;
    downstream.rsp_ready = (_state == PHYSICAL_WAIT);

    if ((_state == IDLE) && translation_bypassed(satp, ctx)) begin
      downstream.req = upstream.req;
      downstream.rsp_ready = upstream.rsp_ready;
      upstream.rsp = '{
          valid: downstream.rsp.valid,
          fault: MMU_FAULT_NONE,
          read_data: downstream.rsp.read_data
      };
    end else if (_state == BYPASS_WAIT) begin
      downstream.rsp_ready = upstream.rsp_ready;
      upstream.rsp = '{
          valid: downstream.rsp.valid,
          fault: MMU_FAULT_NONE,
          read_data: downstream.rsp.read_data
      };
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _ctx <= '0;
      _mmu_request <= '0;
      _vmem_request <= '0;
      _vmem_response <= '0;
      _physical_addr <= '0;
      _mem_request <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (upstream.req.valid && upstream.req_ready) begin
            if (translation_bypassed(satp, ctx)) begin
              if (!(downstream.rsp.valid && upstream.rsp_ready)) begin
                _state <= BYPASS_WAIT;
              end
            end else begin
              _ctx <= ctx;
              _vmem_request <= upstream.req;
              _state <= TRANSLATE_REQUEST;
            end
          end
        end
        BYPASS_WAIT: begin
          if (downstream.rsp.valid && upstream.rsp_ready) begin
            _state <= IDLE;
          end
        end
        TRANSLATE_REQUEST: begin
          _mmu_request <= '{valid: 1'b1, virtual_addr: _vmem_request.addr, ctx: _ctx};
          if (translation.req.valid && translation.req_ready) begin
            _mmu_request <= '0;
            _state <= TRANSLATE_WAIT;
          end
        end
        TRANSLATE_WAIT: begin
          if (translation.rsp.valid) begin
            if (translation.rsp.fault != MMU_FAULT_NONE) begin
              _vmem_response <= '{valid: 1'b1, fault: translation.rsp.fault, read_data: '0};
              _state <= RESPOND;
            end else begin
              _physical_addr <= translation.rsp.physical_addr;
              _state <= PHYSICAL_REQUEST;
            end
          end
        end
        PHYSICAL_REQUEST: begin
          _mem_request <= '{
              valid: 1'b1,
              addr: _physical_addr,
              write_en: _vmem_request.write_en,
              write_data: _vmem_request.write_data,
              write_mask: _vmem_request.write_mask
          };
          if (downstream.req.valid && downstream.req_ready) begin
            _mem_request.valid <= 1'b0;
            _state <= PHYSICAL_WAIT;
          end
        end
        PHYSICAL_WAIT: begin
          if (downstream.rsp.valid) begin
            _vmem_response <= '{
                valid: 1'b1,
                fault: MMU_FAULT_NONE,
                read_data: downstream.rsp.read_data
            };
            _state <= RESPOND;
          end
        end
        RESPOND: begin
          if (_vmem_response.valid && upstream.rsp_ready) begin
            _vmem_response.valid <= 1'b0;
            _state <= IDLE;
          end
        end
        default: begin
        end
      endcase
    end

  end

endmodule
