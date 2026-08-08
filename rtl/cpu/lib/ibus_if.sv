`timescale 1ns / 1ps

interface ibus_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic valid;  // request valid; one fetch at a time
    pc_t  addr;   // instruction fetch byte address
  } req_t;

  typedef struct packed {
    logic   ready;  // instruction response is valid this cycle
    instr_u instr;  // fetched instruction word
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
