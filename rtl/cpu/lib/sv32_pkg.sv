`timescale 1ns / 1ps

package sv32_pkg;
  import riscv_pkg::*;

  // Each policy helper intentionally inspects only the relevant fields of its
  // packed PTE and request arguments.
  /* verilator lint_off UNUSEDSIGNAL */

  function automatic logic translation_bypassed(input satp_t satp, input translation_ctx_t ctx);
    return !satp.mode || (ctx.privilege == PRIV_MACHINE);
  endfunction

  function automatic logic pte_is_invalid(input sv32_pte_t pte);
    return !pte.valid || (!pte.read && pte.write);
  endfunction

  function automatic logic pte_is_leaf(input sv32_pte_t pte);
    return pte.read || pte.execute;
  endfunction

  function automatic logic leaf_is_misaligned(input sv32_pte_t pte, input logic level);
    return level && (pte.ppn0 != '0);
  endfunction

  function automatic logic nonleaf_has_reserved_bits(input sv32_pte_t pte);
    return pte.dirty || pte.accessed || pte.user;
  endfunction

  function automatic logic ppn_is_supported(input logic [21:0] ppn);
    return ppn[21:20] == 2'b00;
  endfunction

  function automatic logic leaf_access_allowed(input sv32_pte_t pte, input mmu_req_t req);
    logic access_allowed;
    logic privilege_allowed;

    case (req.ctx.access)
      MMU_ACCESS_FETCH: begin
        access_allowed = pte.execute;
      end
      MMU_ACCESS_LOAD: begin
        access_allowed = pte.read || (req.ctx.mxr && pte.execute);
      end
      MMU_ACCESS_STORE: begin
        access_allowed = pte.write;
      end
      default: begin
        access_allowed = 1'b0;
      end
    endcase

    case (req.ctx.privilege)
      PRIV_USER: begin
        privilege_allowed = pte.user;
      end

      PRIV_SUPERVISOR: begin
        if (!pte.user) begin
          privilege_allowed = 1'b1;
        end else begin
          privilege_allowed = (req.ctx.access != MMU_ACCESS_FETCH) && req.ctx.sum;
        end
      end

      default: begin
        // Machine mode should have bypassed translation.
        privilege_allowed = 1'b0;
      end
    endcase

    return access_allowed &&
           privilege_allowed &&
           pte.accessed &&
           ((req.ctx.access != MMU_ACCESS_STORE) || pte.dirty);
  endfunction


  function automatic priv_mode_e effective_data_privilege(input priv_mode_e current_privilege,
                                                           input mstatus_t mstatus);
    if ((current_privilege == PRIV_MACHINE) && mstatus.mprv) begin
      return priv_mode_e'(mstatus.mpp);
    end else begin
      return current_privilege;
    end
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

endpackage
