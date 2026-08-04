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

  output csr_data_t   csr_read_data,
  output logic        illegal_csr,
  output csr_status_t status
);

  mstatus_t _mstatus;
  mie_t     _mie;
  mip_t     _mip;
  mtvec_t   _mtvec;
  mepc_t    _mepc;
  mcause_t  _mcause;
  mtval_t   _mtval;

  // verilog_format: off
  localparam mvendorid_t MVENDORID = '0;
  localparam marchid_t   MARCHID   = '0;
  localparam mimpid_t    MIMPID    = '0;
  localparam mhartid_t   MHARTID   = '0;
  // verilog_format: on

  assign status = '{mtvec: _mtvec, mstatus: _mstatus, mie: _mie, mip: _mip};

  always_ff @(posedge clk) begin
    if (rst) begin
      _mstatus <= '0;
      _mie <= '0;
      _mip <= '0;
      _mtvec <= '0;
      _mepc <= '0;
      _mcause <= '0;
      _mtval <= '0;
    end else if (trap_valid) begin
      _mepc   <= trap_mepc;
      _mcause <= trap_mcause;
      _mtval  <= trap_mtval;
    end else if (csr_en && csr_write_en && !illegal_csr) begin
      case (csr_addr_e'(csr_addr))
        CSR_MSTATUS: _mstatus <= csr_write_data;
        CSR_MIE:     _mie <= csr_write_data;
        CSR_MTVEC:   _mtvec <= csr_write_data;
        CSR_MEPC:    _mepc <= csr_write_data;
        CSR_MCAUSE:  _mcause <= csr_write_data;
        CSR_MTVAL:   _mtval <= csr_write_data;
        CSR_MIP:     _mip <= csr_write_data;
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    csr_read_data = '0;
    illegal_csr   = 1'b0;

    if (csr_en && csr_write_en) begin
      case (csr_addr_e'(csr_addr))
        CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP: begin
        end
        default: illegal_csr = 1'b1;
      endcase
    end

    if (csr_en) begin
      case (csr_addr_e'(csr_addr))
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
    end
  end

endmodule
