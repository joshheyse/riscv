`timescale 1ns / 1ps

interface cache_command_if;
  import riscv_pkg::*;

  // A standalone requester or responder necessarily leaves the opposite
  // modport's signals undriven/unused during lint.
  /* verilator lint_off UNDRIVEN */
  /* verilator lint_off UNUSEDSIGNAL */
  logic              valid;
  logic              ready;
  cache_command_op_t op;
  logic              done_valid;
  logic              done_ready;
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_on UNDRIVEN */

  modport requester(output valid, output op, input ready, input done_valid, output done_ready);

  modport responder(input valid, input op, output ready, output done_valid, input done_ready);

endinterface
