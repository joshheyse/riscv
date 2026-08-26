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
module comparator
  import riscv_pkg::*;
(
  input  integer_data_t src_a,
  input  integer_data_t src_b,
  input  logic          sngd,
  output branch_flags_t branch_flags
);

  integer_data_t _af;
  integer_data_t _bf;
  assign _af = {src_a[XLEN-1] ^ sngd, src_a[XLEN-2:0]};
  assign _bf = {src_b[XLEN-1] ^ sngd, src_b[XLEN-2:0]};
  assign branch_flags.eq = (_af == _bf);
  assign branch_flags.lt = (_af < _bf);

endmodule
