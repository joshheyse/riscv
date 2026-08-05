`timescale 1ns / 1ps

module csr_file
  import riscv_pkg::*;
(
  input logic      clk,
  input logic      rst,
  input logic      csr_en,
  input logic      csr_write_en,
  input csr_addr_t csr_addr,
  input csr_data_t csr_write_data,
  input logic      trap_valid,
  input mepc_t     trap_mepc,
  input mcause_t   trap_mcause,
  input mtval_t    trap_mtval,
  input logic      mret_valid,

  output csr_data_t   csr_read_data,
  output logic        illegal_csr,
  output csr_status_t status
);

  mstatus_t   _mstatus;
  mie_t       _mie;
  mip_t       _mip;
  mtvec_t     _mtvec;
  mepc_t      _mepc;
  mcause_t    _mcause;
  mtval_t     _mtval;
  priv_mode_t _priv_mode;
  mstatus_t   _mstatus_write;
  mtvec_t     _mtvec_write;
  csr_addr_t  _csr_addr;

  // verilog_format: off
  localparam mvendorid_t MVENDORID = '0;
  localparam marchid_t   MARCHID   = '0;
  localparam mimpid_t    MIMPID    = '0;
  localparam mhartid_t   MHARTID   = '0;
  // verilog_format: on

  function automatic mstatus_t legalize_mstatus(input logic mie, input logic mpie,
                                                input logic [1:0] mpp);
    legalize_mstatus = '0;
    legalize_mstatus.mie = mie;
    legalize_mstatus.mpie = mpie;

    // `mpp` is WARL. Keep legal privilege encodings; coerce the reserved
    // encoding to machine mode so `mret` cannot restore an invalid live mode.
    case (mpp)
      2'b00:   legalize_mstatus.mpp = MPP_USER;
      2'b01:   legalize_mstatus.mpp = MPP_SUPERVISOR;
      2'b11:   legalize_mstatus.mpp = MPP_MACHINE;
      default: legalize_mstatus.mpp = MPP_MACHINE;
    endcase
  endfunction

  function automatic mtvec_t legalize_mtvec(input logic [29:0] base);
    legalize_mtvec      = '0;
    legalize_mtvec.base = base;
    legalize_mtvec.mode = MTVEC_MODE_DIRECT;
  endfunction

  assign status = '{
          mtvec: _mtvec,
          mstatus: _mstatus,
          mie: _mie,
          mip: _mip,
          mepc: _mepc,
          priv_mode: _priv_mode
      };

  always_comb begin
    _csr_addr      = csr_addr;
    _mstatus_write = legalize_mstatus(csr_write_data[3], csr_write_data[7], csr_write_data[12:11]);
    _mtvec_write   = legalize_mtvec(csr_write_data[31:2]);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _mstatus <= '0;
      _mie <= '0;
      _mip <= '0;
      _mtvec <= '0;
      _mepc <= '0;
      _mcause <= '0;
      _mtval <= '0;
      _priv_mode <= PRIV_MACHINE;
    end else if (trap_valid) begin
      _mepc <= trap_mepc;
      _mcause <= trap_mcause;
      _mtval <= trap_mtval;
      _mstatus.mpie <= _mstatus.mie;
      _mstatus.mie <= 1'b0;
      _mstatus.mpp <= mpp_t'(_priv_mode);
      _priv_mode <= PRIV_MACHINE;
    end else if (mret_valid) begin
      _mstatus.mie <= _mstatus.mpie;
      _mstatus.mpie <= 1'b1;
      _priv_mode <= priv_mode_t'(_mstatus.mpp);
      _mstatus.mpp <= MPP_USER;
    end else if (csr_en && csr_write_en && !illegal_csr) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS: _mstatus <= _mstatus_write;
        CSR_MIE:     _mie <= csr_write_data;
        CSR_MTVEC:   _mtvec <= _mtvec_write;
        CSR_MEPC:    _mepc <= csr_write_data;
        CSR_MCAUSE:  _mcause <= csr_write_data;
        CSR_MTVAL:   _mtval <= csr_write_data;
        CSR_MIP:     _mip <= csr_write_data;
        default: begin
        end
      endcase
      // slang lint_on case-enum-explicit
    end
  end

  always_comb begin
    csr_read_data = '0;
    illegal_csr   = 1'b0;

    if (csr_en && csr_write_en) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP: begin
        end
        default: illegal_csr = 1'b1;
      endcase
      // slang lint_on case-enum-explicit
    end

    if (csr_en) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS:   csr_read_data = _mstatus;
        CSR_MIE:       csr_read_data = _mie;
        CSR_MTVEC:     csr_read_data = _mtvec;
        CSR_MEPC:      csr_read_data = _mepc;
        CSR_MCAUSE:    csr_read_data = _mcause;
        CSR_MTVAL:     csr_read_data = _mtval;
        CSR_MIP:       csr_read_data = _mip;
        CSR_MVENDORID: csr_read_data = MVENDORID;
        CSR_MARCHID:   csr_read_data = MARCHID;
        CSR_MIMPID:    csr_read_data = MIMPID;
        CSR_MHARTID:   csr_read_data = MHARTID;
        default:       illegal_csr = 1'b1;
      endcase
      // slang lint_on case-enum-explicit
    end
  end

endmodule
