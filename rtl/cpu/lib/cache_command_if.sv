`timescale 1ns / 1ps

interface cache_command_if;
  import riscv_pkg::*;

  logic valid;
  logic ready;
  cache_command_op_t op;
  logic done_valid;
  logic done_ready;

  modport requester(output valid, output op, input ready, input done_valid, output done_ready);

  modport responder(input valid, input op, output ready, output done_valid, input done_ready);

endinterface
