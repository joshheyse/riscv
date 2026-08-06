`timescale 1ns / 1ps

interface irq_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic [15:0] platform;
    logic        meip;
    logic        seip;
    logic        mtip;
    logic        stip;
    logic        msip;
    logic        ssip;
    logic        usip;
  } pending_t;

  /* verilator lint_off UNUSEDSIGNAL */
  pending_t pending;
  /* verilator lint_on UNUSEDSIGNAL */

  modport source(output pending);
  modport sink(input pending);

endinterface
