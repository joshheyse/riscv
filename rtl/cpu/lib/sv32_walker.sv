`timescale 1ns / 1ps

// Sv32 page-table walker.
//
// The memory port carries physical PTE accesses and must connect below the
// translation boundary; routing it through a translation adapter would make a
// page-table walk recurse into itself. Each PTE is sampled independently when
// its memory response transfers. The walker does not take an atomic snapshot
// of a multi-level page table or retry when software changes a PTE mid-walk;
// software must synchronize page-table updates and execute SFENCE.VMA.
module sv32_walker
  import riscv_pkg::*;
  import sv32_pkg::*;
(
  input logic  clk,
  input logic  rst,
  /* verilator lint_off UNUSEDSIGNAL */
  input satp_t satp,
  /* verilator lint_on UNUSEDSIGNAL */

  mmu_if.responder translation,
  mem_if.master    memory
);

  typedef enum logic [1:0] {
    IDLE,
    PTE_REQUEST,
    PTE_WAIT,
    RESPOND
  } state_e;
  state_e      _state;

  mmu_rsp_t    _response;
  mmu_req_t    _request;
  sv32_level_e _level;
  sv32_ppn_t   _table_ppn;
  logic        _global_mapping;

  mem_req_t    _memory_request;

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
      _global_mapping <= 1'b0;
    end else begin
      case (_state)
        IDLE: begin
          if (translation.req.valid && translation.req_ready) begin
            if (translation_bypassed(satp, translation.req.ctx)) begin
              _response <= '{
                  valid: 1'b1,
                  fault: MMU_FAULT_NONE,
                  physical_addr: translation.req.virtual_addr.raw,
                  leaf_level: SV32_LEVEL_0,
                  leaf_pte: '0
              };
              _state <= RESPOND;
            end else begin
              _request        <= translation.req;
              _level          <= SV32_LEVEL_1;
              _table_ppn      <= satp.ppn;
              _global_mapping <= 1'b0;
              _state          <= PTE_REQUEST;
            end
          end
        end
        PTE_REQUEST: begin
          mem_addr_t pte_addr;

          pte_addr = {
            _table_ppn[19:0],
            (_level == SV32_LEVEL_1) ? _request.virtual_addr.fields.vpn.vpn1 :
                                       _request.virtual_addr.fields.vpn.vpn0,
            2'b00
          };
          if (!ppn_is_supported(_table_ppn)) begin
            _response <= '{
                valid: 1'b1,
                fault: MMU_FAULT_ACCESS,
                physical_addr: '0,
                leaf_level: SV32_LEVEL_0,
                leaf_pte: '0
            };
            _state <= RESPOND;
          end else begin
            _memory_request.valid <= 1'b1;
            _memory_request.addr <= pte_addr;
            _memory_request.size <= MEM_SIZE_WORD;
            _memory_request.access <= MMU_ACCESS_LOAD;
            _memory_request.privilege <= PRIV_SUPERVISOR;
            _memory_request.write_en <= 1'b0;
            _memory_request.write_data <= '0;
            _memory_request.write_mask <= '0;
            if (memory.req.valid && memory.req_ready) begin
              _memory_request.valid <= 1'b0;
              _state                <= PTE_WAIT;
            end
          end
        end
        PTE_WAIT: begin
          if (memory.rsp.valid && memory.rsp_ready) begin
            if (memory.rsp.fault != MMU_FAULT_NONE) begin
              _response <= '{
                  valid: 1'b1,
                  fault: memory.rsp.fault,
                  physical_addr: '0,
                  leaf_level: SV32_LEVEL_0,
                  leaf_pte: '0
              };
              _state <= RESPOND;
            end else begin
              sv32_pte_t pte;
              pte = sv32_pte_t'(memory.rsp.read_data);
              pte.global_mapping = pte.global_mapping || _global_mapping;
              if (pte_is_invalid(pte)) begin
                _response <= '{
                    valid: 1'b1,
                    fault: MMU_FAULT_PAGE,
                    physical_addr: '0,
                    leaf_level: SV32_LEVEL_0,
                    leaf_pte: '0
                };
                _state <= RESPOND;
              end else if (pte_is_leaf(pte)) begin
                if (!leaf_access_allowed(pte, _request) || leaf_is_misaligned(pte, _level)) begin
                  _response <= '{
                      valid: 1'b1,
                      fault: MMU_FAULT_PAGE,
                      physical_addr: '0,
                      leaf_level: SV32_LEVEL_0,
                      leaf_pte: '0
                  };
                  _state <= RESPOND;
                end else if (!ppn_is_supported(pte.ppn)) begin
                  _response <= '{
                      valid: 1'b1,
                      fault: MMU_FAULT_ACCESS,
                      physical_addr: '0,
                      leaf_level: SV32_LEVEL_0,
                      leaf_pte: '0
                  };
                  _state <= RESPOND;
                end else begin
                  _response <= '{
                      valid: 1'b1,
                      fault: MMU_FAULT_NONE,
                      physical_addr: leaf_physical_address(pte, _level, _request.virtual_addr),
                      leaf_level: _level,
                      leaf_pte: pte
                  };
                  _state <= RESPOND;
                end
              end else if (nonleaf_has_reserved_bits(pte) || (_level == SV32_LEVEL_0)) begin
                _response <= '{
                    valid: 1'b1,
                    fault: MMU_FAULT_PAGE,
                    physical_addr: '0,
                    leaf_level: SV32_LEVEL_0,
                    leaf_pte: '0
                };
                _state <= RESPOND;
              end else if (!ppn_is_supported(pte.ppn)) begin
                _response <= '{
                    valid: 1'b1,
                    fault: MMU_FAULT_ACCESS,
                    physical_addr: '0,
                    leaf_level: SV32_LEVEL_0,
                    leaf_pte: '0
                };
                _state <= RESPOND;
              end else begin
                _table_ppn <= pte.ppn;
                _global_mapping <= _global_mapping || pte.global_mapping;
                _level <= SV32_LEVEL_0;
                _state <= PTE_REQUEST;
              end
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
