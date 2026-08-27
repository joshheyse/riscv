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
  input  flow_e         flow,
  input  branch_flags_t flags,
  input  br_funct3_t    funct3,
  output pc_src_e       pc_src
);

  logic _cmp_flag;
  logic _cond_met;
  logic _encoding_valid;

  assign _cmp_flag = funct3.use_lt ? flags.lt : flags.eq;
  assign _encoding_valid = funct3.use_lt | ~funct3.unsgnd;
  assign _cond_met = _encoding_valid && (_cmp_flag ^ funct3.invert);
  assign pc_src = ((_cond_met && (flow == FLOW_BRANCH)) || (flow == FLOW_JUMP))
                ? PC_SRC_IEU_ADR
                : PC_SRC_INC;

endmodule
