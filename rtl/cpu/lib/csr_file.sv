`timescale 1ns / 1ps

module csr_file
  import riscv_pkg::*;
  import csr_legalize_pkg::*;
(
  input logic      clk,
  input logic      rst,
  input logic      csr_en,
  input logic      csr_write_en,
  input csr_addr_u csr_addr,
  input csr_data_t csr_write_data,
  input logic      trap_valid,
  input trap_t     trap,
  input logic      mret_valid,
  input logic      sret_valid,
  input dword_t    time_value,
  input logic      retire,

  output csr_data_t   csr_read_data,
  output logic        illegal_csr,
  output csr_status_t status
);

  mstatus_t   _mstatus;
  mie_t       _mie;
  mip_t       _mip;
  tvec_t      _mtvec;
  epc_t       _mepc;
  cause_t     _mcause;
  tval_t      _mtval;
  word_t      _medeleg;
  word_t      _mideleg;
  priv_mode_e _priv_mode;
  mstatus_t   _mstatus_write;
  // Supervisor status aliases only the implemented shared mstatus fields.
  /* verilator lint_off UNUSEDSIGNAL */
  sstatus_t   _sstatus_write;
  /* verilator lint_on UNUSEDSIGNAL */
  mie_t       _mie_write;
  mip_t       _mip_write;
  tvec_t      _mtvec_write;
  csr_addr_u  _csr_addr;

  sstatus_t   _sstatus;
  tvec_t      _stvec;
  epc_t       _sepc;
  cause_t     _scause;
  tval_t      _stval;
  word_t      _sscratch;
  satp_t      _satp;
  counteren_t _mcounteren;
  counteren_t _scounteren;
  dword_t     _mcycle;
  dword_t     _minstret;

  // verilog_format: off
  localparam mvendorid_t MVENDORID = '0;
  localparam marchid_t   MARCHID   = '0;
  localparam mimpid_t    MIMPID    = '0;
  localparam mhartid_t   MHARTID   = '0;
  // Delegatable exceptions implemented by this core: instruction-address
  // misaligned, illegal instruction, breakpoint, load/store-address
  // misaligned, U/S-mode ECALL, and instruction/load/store page faults.
  // M-mode ECALL cannot delegate downward.
  localparam word_t      MEDELEG_WRITABLE_MASK = 32'h0000_b35d;
  localparam word_t      MIDELEG_WRITABLE_MASK = 32'h0000_0222;
  // verilog_format: on

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
          priv_mode: _priv_mode,
          satp: _satp,
          mcounteren: _mcounteren,
          scounteren: _scounteren
      };

  always_comb begin
    _csr_addr = csr_addr;
    _mstatus_write = build_legal_mstatus(csr_write_data);
    _sstatus_write = build_legal_sstatus(csr_write_data);
    _mie_write = build_legal_mie(csr_write_data);
    _mip_write = build_legal_mip(csr_write_data);
    _mtvec_write = build_legal_tvec(csr_write_data);
    _sstatus = '0;
    _sstatus.sie = _mstatus.sie;
    _sstatus.spie = _mstatus.spie;
    _sstatus.spp = _mstatus.spp;
    _sstatus.sum = _mstatus.sum;
    _sstatus.mxr = _mstatus.mxr;
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
      _sscratch <= '0;
      _satp <= '0;
      _mcounteren <= '0;
      _scounteren <= '0;
      _mcycle <= '0;
      _minstret <= '0;
      _priv_mode <= PRIV_MACHINE;
    end else begin
      _mcycle <= _mcycle + 1'b1;
      if(retire) begin
        _minstret <= _minstret + 1'b1;
      end
      if (trap_valid) begin
        // slang lint_off case-enum-explicit
        case (trap.target_priv)
          PRIV_SUPERVISOR: begin
            _sepc <= trap.epc;
            _scause <= trap.cause;
            _stval <= trap.tval;
            _mstatus.spie <= _mstatus.sie;
            _mstatus.sie <= 1'b0;
            _mstatus.spp <= _priv_mode == PRIV_SUPERVISOR;
            _priv_mode <= PRIV_SUPERVISOR;
          end
          default: begin
            _mepc <= trap.epc;
            _mcause <= trap.cause;
            _mtval <= trap.tval;
            _mstatus.mpie <= _mstatus.mie;
            _mstatus.mie <= 1'b0;
            _mstatus.mpp <= mpp_e'(_priv_mode);
            _priv_mode <= PRIV_MACHINE;
          end
          // slang lint_on case-enum-explicit
        endcase
      end else if (mret_valid) begin
        if (_mstatus.mpp != MPP_MACHINE) begin
          _mstatus.mprv <= 1'b0;
        end
        _mstatus.mie <= _mstatus.mpie;
        _mstatus.mpie <= 1'b1;
        _priv_mode <= priv_mode_e'(_mstatus.mpp);
        _mstatus.mpp <= MPP_USER;
      end else if (sret_valid) begin
        _mstatus.sie  <= _mstatus.spie;
        _mstatus.spie <= 1'b1;
        _priv_mode    <= _mstatus.spp ? PRIV_SUPERVISOR : PRIV_USER;
        _mstatus.spp  <= 1'b0;
      end else if (csr_en && csr_write_en && !illegal_csr) begin
        // slang lint_off case-enum-explicit
        case (_csr_addr.named)
          CSR_MSTATUS:  _mstatus <= _mstatus_write;
          CSR_SSTATUS: begin
            _mstatus.sie  <= _sstatus_write.sie;
            _mstatus.spie <= _sstatus_write.spie;
            _mstatus.spp  <= _sstatus_write.spp;
            _mstatus.sum  <= _sstatus_write.sum;
            _mstatus.mxr  <= _sstatus_write.mxr;
          end
          CSR_MEDELEG:  _medeleg <= csr_write_data & MEDELEG_WRITABLE_MASK;
          CSR_MIDELEG:  _mideleg <= csr_write_data & MIDELEG_WRITABLE_MASK;
          CSR_MIE:      _mie <= _mie_write;
          CSR_SIE: begin
            _mie.ssip <= _mie_write.ssip;
            _mie.stip <= _mie_write.stip;
            _mie.seip <= _mie_write.seip;
          end
          CSR_MTVEC:    _mtvec <= _mtvec_write;
          CSR_STVEC:    _stvec <= build_legal_tvec(csr_write_data);
          CSR_SSCRATCH: _sscratch <= csr_write_data;
          CSR_MEPC:     _mepc <= csr_write_data;
          CSR_SEPC:     _sepc <= csr_write_data;
          CSR_MCAUSE:   _mcause <= csr_write_data;
          CSR_SCAUSE:   _scause <= csr_write_data;
          CSR_MTVAL:    _mtval <= csr_write_data;
          CSR_STVAL:    _stval <= csr_write_data;
          CSR_MIP:      _mip <= _mip_write;
          CSR_SIP: begin
            _mip.ssip <= _mip_write.ssip;
            _mip.stip <= _mip_write.stip;
            _mip.seip <= _mip_write.seip;
          end
          CSR_SATP: begin
            _satp <= build_legal_satp(csr_write_data);
          end
          CSR_MCOUNTEREN:      _mcounteren <= build_legal_counteren(csr_write_data);
          CSR_SCOUNTEREN:      _scounteren <= build_legal_counteren(csr_write_data);
          CSR_MCYCLE:          _mcycle[31:0] <= csr_write_data;
          CSR_MCYCLEH:         _mcycle[63:32] <= csr_write_data;
          CSR_MINSTRET:        _minstret[31:0] <= csr_write_data;
          CSR_MINSTRETH:       _minstret[63:32] <= csr_write_data;
          default: begin
          end
        endcase
        // slang lint_on case-enum-explicit
      end
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
            CSR_STVAL, CSR_SIP, CSR_SATP, CSR_SSCRATCH, CSR_MCOUNTEREN, CSR_SCOUNTEREN,
            CSR_MCYCLE, CSR_MCYCLEH, CSR_MINSTRET, CSR_MINSTRETH: begin
        end
        default: illegal_csr = 1'b1;
      endcase
      // slang lint_on case-enum-explicit
    end

    if (csr_en) begin
      // slang lint_off case-enum-explicit
      case (_csr_addr.named)
        CSR_MSTATUS:    csr_read_data = _mstatus;
        CSR_MEDELEG:    csr_read_data = _medeleg;
        CSR_MIDELEG:    csr_read_data = _mideleg;
        CSR_MIE:        csr_read_data = _mie;
        CSR_MTVEC:      csr_read_data = _mtvec;
        CSR_MEPC:       csr_read_data = _mepc;
        CSR_MCAUSE:     csr_read_data = _mcause;
        CSR_MTVAL:      csr_read_data = _mtval;
        CSR_MIP:        csr_read_data = _mip;
        CSR_SATP:       csr_read_data = _satp;
        CSR_SSTATUS:    csr_read_data = _sstatus;
        CSR_SIE:        csr_read_data = word_t'(_mie) & _mideleg;
        CSR_STVEC:      csr_read_data = _stvec;
        CSR_SEPC:       csr_read_data = _sepc;
        CSR_SCAUSE:     csr_read_data = _scause;
        CSR_STVAL:      csr_read_data = _stval;
        CSR_SIP:        csr_read_data = word_t'(_mip) & _mideleg;
        CSR_SSCRATCH:   csr_read_data = _sscratch;
        CSR_MVENDORID:  csr_read_data = MVENDORID;
        CSR_MARCHID:    csr_read_data = MARCHID;
        CSR_MIMPID:     csr_read_data = MIMPID;
        CSR_MHARTID:    csr_read_data = MHARTID;
        CSR_MCOUNTEREN: csr_read_data = _mcounteren;
        CSR_SCOUNTEREN: csr_read_data = _scounteren;
        CSR_TIME:       csr_read_data = time_value[31:0];
        CSR_TIMEH:      csr_read_data = time_value[63:32];
        CSR_MCYCLE:     csr_read_data = _mcycle[31:0];
        CSR_MCYCLEH:    csr_read_data = _mcycle[63:32];
        CSR_CYCLE:      csr_read_data = _mcycle[31:0];
        CSR_CYCLEH:     csr_read_data = _mcycle[63:32];
        CSR_MINSTRET:   csr_read_data = _minstret[31:0];
        CSR_MINSTRETH:  csr_read_data = _minstret[63:32];
        CSR_INSTRET:    csr_read_data = _minstret[31:0];
        CSR_INSTRETH:   csr_read_data = _minstret[63:32];
        default:        illegal_csr = 1'b1;
      endcase
      // slang lint_on case-enum-explicit
    end
  end

  wire _unused_signal = &{1'b0, trap.handler_pc};

endmodule
