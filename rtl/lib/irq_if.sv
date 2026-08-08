`timescale 1ns / 1ps

interface irq_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic [15:0] platform;   // custom/platform-specific interrupt pending bits (reserved extension space)
    logic meip;  // machine-level external interrupt pending (M-mode)
    logic seip;  // supervisor-level external interrupt pending (S-mode)
    logic mtip;  // machine-level timer interrupt pending (M-mode)
    logic stip;  // supervisor-level timer interrupt pending (S-mode)
    logic msip;  // machine-level software interrupt pending (M-mode)
    logic ssip;  // supervisor-level software interrupt pending (S-mode)
    logic usip;  // user-level software interrupt pending (U-mode)
  } pending_t;

  /* verilator lint_off UNUSEDSIGNAL */
  pending_t pending;
  /* verilator lint_on UNUSEDSIGNAL */

  modport source(output pending);
  modport sink(input pending);

endinterface
