`timescale 1ns / 1ps

module integer_execute
  import riscv_pkg::*;
(
  /* verilator lint_off UNUSEDSIGNAL */
  input control_t   ctrl,
  /* verilator lint_on UNUSEDSIGNAL */
  input br_funct3_t branch_funct3,
  input pc_t        pc,
  input reg_data_t  rs1_data,
  input reg_data_t  rs2_data,
  input imm_t       imm,

  output alu_data_t alu_result,
  output mem_data_t store_data,
  output pc_src_t   pc_src
);

  alu_data_t     _src_a;
  alu_data_t     _src_b;
  branch_flags_t _branch_flags;

  assign _src_a = ctrl.alu_operands[1] ? pc : rs1_data;
  assign _src_b = ctrl.alu_operands[0] ? imm : rs2_data;
  assign store_data = rs2_data;

  alu_execute _alu_execute (
    .src_a(_src_a),
    .src_b(_src_b),
    .ctrl(ctrl.alu),
    .alu_result(alu_result)
  );

  comparator _execute_comparator (
    .src_a(rs1_data),
    .src_b(rs2_data),
    .sngd(ctrl.branch_sgnd),
    .branch_flags(_branch_flags)
  );

  branch_logic _execute_branch_logic (
    .flow(ctrl.flow),
    .flags(_branch_flags),
    .funct3(branch_funct3),
    .pc_src(pc_src)
  );

endmodule
