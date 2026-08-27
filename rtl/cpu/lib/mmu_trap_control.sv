`timescale 1ns / 1ps

// Convert an MMU response fault into the corresponding architectural trap
// request. Trap delegation and vector resolution remain in trap_control.
module mmu_trap_control
  import riscv_pkg::*;
(
  input mmu_fault_t  fault,
  input mmu_access_t access,
  input mem_addr_t   virtual_addr,

  output trap_req_t trap_req
);

  always_comb begin
    trap_req = '{valid: fault != MMU_FAULT_NONE, src: TRAP_SRC_NONE, tval: virtual_addr};

    case (fault)
      MMU_FAULT_PAGE: begin
        case (access)
          MMU_ACCESS_FETCH: trap_req.src = TRAP_SRC_INSTR_PAGE_FAULT;
          MMU_ACCESS_LOAD:  trap_req.src = TRAP_SRC_LOAD_PAGE_FAULT;
          MMU_ACCESS_STORE: trap_req.src = TRAP_SRC_STORE_PAGE_FAULT;
          default:          trap_req.src = TRAP_SRC_NONE;
        endcase
      end
      MMU_FAULT_ACCESS: begin
        case (access)
          MMU_ACCESS_FETCH: trap_req.src = TRAP_SRC_INSTR_ACCESS_FAULT;
          MMU_ACCESS_LOAD:  trap_req.src = TRAP_SRC_LOAD_ACCESS_FAULT;
          MMU_ACCESS_STORE: trap_req.src = TRAP_SRC_STORE_ACCESS_FAULT;
          default:          trap_req.src = TRAP_SRC_NONE;
        endcase
      end
      default: begin
      end
    endcase
  end

endmodule
