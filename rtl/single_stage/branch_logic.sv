`timescale 1ns / 1ps

module branch_logic
  import riscv_pkg::*;
(
  input logic branch,
  input logic jump,
  input branch_flags_t flags,
  input br_funct3_t funct3,
  output pc_src_t pc_src
);

  logic cmp_flag;
  logic cond_met;
  logic encoding_valid;

  assign cmp_flag = funct3.use_lt ? flags.lt : flags.eq;
  assign encoding_valid = funct3.use_lt | ~funct3.unsgnd;
  assign cond_met = (cmp_flag ^ funct3.invert) & encoding_valid;
  assign pc_src = ((cond_met & branch) | jump) ? PC_SRC_IEU_ADR : PC_SRC_INC;

endmodule
