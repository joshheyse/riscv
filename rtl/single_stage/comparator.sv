`timescale 1ns / 1ps

module comparator
  import riscv_pkg::*;
(
  input  word_t src_a,
  input  word_t src_b,
  input  logic  sngd,
  output logic  eq,
  output logic  lt
);

  word_t af;
  word_t bf;
  assign af = {src_a[XLEN-1] ^ sngd, src_a[XLEN-2:0]};
  assign bf = {src_b[XLEN-1] ^ sngd, src_b[XLEN-2:0]};
  assign eq = (af == bf);
  assign lt = (af < bf);

endmodule
