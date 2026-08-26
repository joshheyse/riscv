`timescale 1ns / 1ps

module sv32_walker
  import riscv_pkg::*;
  import sv32_pkg::*;
(
  input logic  clk,
  input logic  rst,
  input satp_t satp,

  mmu_if.responder translation,
  mem_if.master    memory
);

  typedef enum logic [1:0] {
    IDLE,
    PTE_REQUEST,
    PTE_WAIT,
    RESPOND
  } state_t;
  state_t          _state;

  mmu_rsp_t        _response;
  mmu_req_t        _request;
  logic            _level;
  logic     [21:0] _table_ppn;

  mem_req_t        _memory_request;

  always_comb begin
    translation.rsp       = _response;
    translation.req_ready = (_state == IDLE);
    memory.req            = _memory_request;
    memory.rsp_ready      = (_state == PTE_WAIT);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _response <= '0;
      _memory_request <= '0;
    end else begin
      case (_state)
        IDLE: begin
          if (translation.req.valid && translation.req_ready) begin
            if (satp.mode == 1'b0 || (translation.req.privilege == PRIV_MACHINE)) begin
              _response <= '{
                  valid: 1'b1,
                  fault: MMU_FAULT_NONE,
                  physical_addr: translation.req.virtual_addr.raw
              };
              _state <= RESPOND;
            end else begin
              _request   <= translation.req;
              _level     <= 1'b1;
              _table_ppn <= satp.ppn;
              _state     <= PTE_REQUEST;
            end
          end
        end
        PTE_REQUEST: begin
          if (!ppn_is_supported(_table_ppn)) begin
            _response <= '{valid: 1'b1, fault: MMU_FAULT_ACCESS, physical_addr: '0};
            _state    <= RESPOND;
          end else begin
            _memory_request.valid <= 1'b1;
            _memory_request.addr <= {
              _table_ppn[19:0],
              _level ? _request.virtual_addr.named.vpn1 : _request.virtual_addr.named.vpn0,
              2'b00
            };
            if (memory.req.valid && memory.req_ready) begin
              _memory_request.valid <= 1'b0;
              _state                <= PTE_WAIT;
            end
          end
        end
        PTE_WAIT: begin
          if (memory.rsp.valid && memory.rsp_ready) begin
            sv32_pte_t pte;
            pte = sv32_pte_t'(memory.rsp.read_data);
            if (pte_is_invalid(pte)) begin
              _response <= '{valid: 1'b1, fault: MMU_FAULT_PAGE, physical_addr: '0};
              _state <= RESPOND;
            end else if (pte_is_leaf(pte)) begin
              if (!leaf_access_allowed(pte, _request) || leaf_is_misaligned(pte, _level)) begin
                _response <= '{valid: 1'b1, fault: MMU_FAULT_PAGE, physical_addr: '0};
                _state    <= RESPOND;
              end else if (!ppn_is_supported({pte.ppn1, pte.ppn0})) begin
                _response <= '{valid: 1'b1, fault: MMU_FAULT_ACCESS, physical_addr: '0};
                _state    <= RESPOND;
              end else begin
                _response <= '{
                    valid: 1'b1,
                    fault: MMU_FAULT_NONE,
                    physical_addr: {
                      pte.ppn1[9:0],
                      _level ? _request.virtual_addr.named.vpn0 : pte.ppn0,
                      _request.virtual_addr.named.offset
                    }
                };
                _state <= RESPOND;
              end
            end else if (nonleaf_has_reserved_bits(pte) || !_level) begin
              _response <= '{valid: 1'b1, fault: MMU_FAULT_PAGE, physical_addr: '0};
              _state    <= RESPOND;
            end else if (!ppn_is_supported({pte.ppn1, pte.ppn0})) begin
              _response <= '{valid: 1'b1, fault: MMU_FAULT_ACCESS, physical_addr: '0};
              _state    <= RESPOND;
            end else begin
              _memory_request.valid <= 1'b1;
              _memory_request.addr <= {
                pte.ppn1[9:0], pte.ppn0, _request.virtual_addr.named.vpn0, 2'b00
              };
              _table_ppn <= {pte.ppn1, pte.ppn0};
              _level <= 1'b0;
              _state <= PTE_REQUEST;
            end
          end
        end
        RESPOND: begin
          if (_response.valid && translation.rsp_ready) begin
            _response.valid <= 1'b0;
            _state <= IDLE;
          end
        end
        default: begin
        end
      endcase
    end
  end

endmodule
