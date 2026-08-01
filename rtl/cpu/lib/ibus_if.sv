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

  req_t req;
  rsp_t rsp;

  modport master(output req, input rsp);

  modport slave(input req, output rsp);

endinterface
