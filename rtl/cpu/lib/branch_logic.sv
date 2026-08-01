`timescale 1ns / 1ps

// Branch/jump PC-select logic.
//
// The comparator has already produced `eq` and `lt`; for BLTU/BGEU the
// comparator's signedness input is driven unsigned before the flags arrive
// here. This module only applies the branch funct3 condition and ORs in jumps.
//
//   funct3  instruction  uses flag  invert  valid
//   ------  -----------  ---------  ------  -----
//   000     beq          eq         0       yes
//   001     bne          eq         1       yes
//   010     reserved     eq         0       no
//   011     reserved     eq         1       no
//   100     blt          lt         0       yes
//   101     bge          lt         1       yes
//   110     bltu         lt         0       yes
//   111     bgeu         lt         1       yes
//
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
