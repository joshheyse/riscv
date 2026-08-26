`timescale 1ns / 1ps

package csr_legalize_pkg;

  import riscv_pkg::*;

  // Legalization intentionally ignores unsupported and WPRI input fields.
  /* verilator lint_off UNUSEDSIGNAL */

  function automatic mstatus_t build_legal_mstatus(input csr_data_t csr_write_data);
    mstatus_t requested;
    mstatus_t result;

    requested = mstatus_t'(csr_write_data);
    result = '0;
    result.mie = requested.mie;
    result.mpie = requested.mpie;
    result.sie = requested.sie;
    result.spie = requested.spie;
    result.spp = requested.spp;
    result.tsr = requested.tsr;
    result.tvm = requested.tvm;
    result.sum = requested.sum;
    result.mxr = requested.mxr;
    result.mprv = requested.mprv;

    // `mpp` is WARL. Keep legal privilege encodings; coerce the reserved
    // encoding to machine mode so `mret` cannot restore an invalid live mode.
    case (requested.mpp)
      MPP_USER:       result.mpp = MPP_USER;
      MPP_SUPERVISOR: result.mpp = MPP_SUPERVISOR;
      MPP_MACHINE:    result.mpp = MPP_MACHINE;
      default:        result.mpp = MPP_MACHINE;
    endcase

    return result;
  endfunction

  function automatic sstatus_t build_legal_sstatus(input csr_data_t csr_write_data);
    sstatus_t requested;
    sstatus_t result;

    requested = sstatus_t'(csr_write_data);
    result = '0;
    result.sie = requested.sie;
    result.spie = requested.spie;
    result.spp = requested.spp;
    result.sum = requested.sum;
    result.mxr = requested.mxr;
    return result;
  endfunction

  function automatic mie_t build_legal_mie(input csr_data_t csr_write_data);
    return mie_t'(csr_write_data);
  endfunction

  function automatic mip_t build_legal_mip(input csr_data_t csr_write_data);
    return mip_t'(csr_write_data);
  endfunction

  function automatic tvec_t build_legal_tvec(input csr_data_t csr_write_data);
    tvec_t result;

    result      = '0;
    result.base = csr_write_data[31:2];
    result.mode = TVEC_MODE_DIRECT;
    return result;
  endfunction

  function automatic satp_t build_legal_satp(input csr_data_t csr_write_data);
    satp_t result;

    result = satp_t'(csr_write_data);
    // ASIDs are not implemented until the TLB can tag translations with them.
    result.asid = '0;
    return result;
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

endpackage
