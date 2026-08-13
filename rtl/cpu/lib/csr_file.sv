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
  input logic      sret_valid,

  output csr_data_t   csr_read_data,
  output logic        illegal_csr,
  output csr_status_t status
);

  mstatus_t   _mstatus;
  sstatus_t   _sstatus;
  mie_t       _mie;
  mip_t       _mip;
  mtvec_t     _mtvec;
  mtvec_t     _stvec;
  mepc_t      _mepc;
  sepc_t      _sepc;
  mcause_t    _mcause;
  mcause_t    _scause;
  mtval_t     _mtval;
  mtval_t     _stval;
  word_t      _medeleg;
  word_t      _mideleg;
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
                                                input logic [1:0] mpp, input logic sie,
                                                input logic spie, input logic spp);
    legalize_mstatus = '0;
    legalize_mstatus.mie = mie;
    legalize_mstatus.mpie = mpie;
    legalize_mstatus.sie  = sie;
    legalize_mstatus.spie = spie;
    legalize_mstatus.spp  = spp;

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
          stvec: _stvec,
          mstatus: _mstatus,
          mie: _mie,
          mip: _mip,
          mepc: _mepc,
          sepc: _sepc,
          medeleg: _medeleg,
          mideleg: _mideleg,
          priv_mode: _priv_mode
      };

  always_comb begin
    _csr_addr      = csr_addr;
    _mstatus_write = legalize_mstatus(csr_write_data[3], csr_write_data[7],
                                      csr_write_data[12:11], csr_write_data[1],
                                      csr_write_data[5], csr_write_data[8]);
    _mtvec_write   = legalize_mtvec(csr_write_data[31:2]);
    _sstatus       = '0;
    _sstatus.sie   = _mstatus.sie;
    _sstatus.spie  = _mstatus.spie;
    _sstatus.spp   = _mstatus.spp;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _mstatus <= '0;
      _mie <= '0;
      _mip <= '0;
      _mtvec <= '0;
      _stvec <= '0;
      _mepc <= '0;
      _sepc <= '0;
      _mcause <= '0;
      _scause <= '0;
      _mtval <= '0;
      _stval <= '0;
      _medeleg <= '0;
      _mideleg <= '0;
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
    end else if (sret_valid) begin
      _mstatus.sie  <= _mstatus.spie;
      _mstatus.spie <= 1'b1;
      _priv_mode    <= _mstatus.spp ? PRIV_SUPERVISOR : PRIV_USER;
      _mstatus.spp  <= 1'b0;
    end else if (csr_en && csr_write_en && !illegal_csr) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS: _mstatus <= _mstatus_write;
        CSR_SSTATUS: begin
          _mstatus.sie  <= csr_write_data[1];
          _mstatus.spie <= csr_write_data[5];
          _mstatus.spp  <= csr_write_data[8];
        end
        CSR_MEDELEG: _medeleg <= csr_write_data;
        CSR_MIDELEG: _mideleg <= csr_write_data;
        CSR_MIE:     _mie <= csr_write_data;
        CSR_SIE: begin
          _mie.ssip <= csr_write_data[1];
          _mie.stip <= csr_write_data[5];
          _mie.seip <= csr_write_data[9];
        end
        CSR_MTVEC:   _mtvec <= _mtvec_write;
        CSR_STVEC:   _stvec <= legalize_mtvec(csr_write_data[31:2]);
        CSR_MEPC:    _mepc <= csr_write_data;
        CSR_SEPC:    _sepc <= csr_write_data;
        CSR_MCAUSE:  _mcause <= csr_write_data;
        CSR_SCAUSE:  _scause <= csr_write_data;
        CSR_MTVAL:   _mtval <= csr_write_data;
        CSR_STVAL:   _stval <= csr_write_data;
        CSR_MIP:     _mip <= csr_write_data;
        CSR_SIP: begin
          _mip.ssip <= csr_write_data[1];
          _mip.stip <= csr_write_data[5];
          _mip.seip <= csr_write_data[9];
        end
        CSR_SATP: begin
        end
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
        CSR_MSTATUS, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE,
            CSR_MTVAL, CSR_MIP, CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SEPC, CSR_SCAUSE,
            CSR_STVAL, CSR_SIP, CSR_SATP: begin
        end
        default: illegal_csr = 1'b1;
      endcase
      // slang lint_on case-enum-explicit
    end

    if (csr_en) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS:   csr_read_data = _mstatus;
        CSR_MEDELEG:   csr_read_data = _medeleg;
        CSR_MIDELEG:   csr_read_data = _mideleg;
        CSR_MIE:       csr_read_data = _mie;
        CSR_MTVEC:     csr_read_data = _mtvec;
        CSR_MEPC:      csr_read_data = _mepc;
        CSR_MCAUSE:    csr_read_data = _mcause;
        CSR_MTVAL:     csr_read_data = _mtval;
        CSR_MIP:       csr_read_data = _mip;
        CSR_SATP:      csr_read_data = 32'h0000_0000;
        CSR_SSTATUS:   csr_read_data = _sstatus;
        CSR_SIE:       csr_read_data = _mie & _mideleg;
        CSR_STVEC:     csr_read_data = _stvec;
        CSR_SEPC:      csr_read_data = _sepc;
        CSR_SCAUSE:    csr_read_data = _scause;
        CSR_STVAL:     csr_read_data = _stval;
        CSR_SIP:       csr_read_data = _mip & _mideleg;
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
