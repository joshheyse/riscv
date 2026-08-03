`timescale 1ns / 1ps

interface ibus_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic valid;
    pc_t  addr;
  } req_t;

  typedef struct packed {
    logic   ready;
    instr_u instr;
  } rsp_t;

  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  req_t req;
  rsp_t rsp;
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  modport master(output req, input rsp);

  modport slave(input req, output rsp);

endinterface
