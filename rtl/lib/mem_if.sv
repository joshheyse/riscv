`timescale 1ns / 1ps

interface mem_if
  import riscv_pkg::*;
();

  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  mem_req_t req;
  mem_rsp_t rsp;
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  modport master(output req, input rsp);
  modport slave(input req, output rsp);

endinterface
