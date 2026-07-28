`timescale 1ns / 1ps

// Two-flag comparator for branch decisions.
//
// `eq` is independent of signedness. `lt` is signed when `sngd=1` and unsigned
// when `sngd=0`. The sign-bit transform lets a single unsigned comparison
// implement both:
//
//   sngd  comparison used by branches
//   ----  ---------------------------
//   0     BLTU/BGEU unsigned compare
//   1     BLT/BGE signed compare
//
module comparator (
  input riscv_pkg::word_t src_a,
  input riscv_pkg::word_t src_b,
  input logic sngd,
  output logic eq,
  output logic lt
);

  riscv_pkg::word_t af;
  riscv_pkg::word_t bf;
  assign af = {src_a[riscv_pkg::XLEN-1] ^ sngd, src_a[riscv_pkg::XLEN-2:0]};
  assign bf = {src_b[riscv_pkg::XLEN-1] ^ sngd, src_b[riscv_pkg::XLEN-2:0]};
  assign eq = (af == bf);
  assign lt = (af < bf);

endmodule
