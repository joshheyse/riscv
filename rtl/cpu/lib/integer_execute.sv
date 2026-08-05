`timescale 1ns / 1ps

module integer_execute
  import riscv_pkg::*;
(
  input control_t   ctrl,
  input br_funct3_t branch_funct3,
  input pc_t        pc,
  input reg_data_t  rs1_data,
  input reg_data_t  rs2_data,
  input imm_t       imm,

  output alu_data_t     alu_result,
  output mem_data_t     store_data,
  output branch_flags_t branch_flags,
  output pc_src_t       pc_src
);

  alu_data_t _src_a;
  alu_data_t _src_b;

  assign _src_a = ctrl.alu_operands[1] ? pc : rs1_data;
  assign _src_b = ctrl.alu_operands[0] ? imm : rs2_data;
  assign store_data = rs2_data;

  alu _alu (
    .src_a(_src_a),
    .src_b(_src_b),
    .alu_op(ctrl.alu_op),
    .sub_arith(ctrl.sub_arith),
    .alu_result(alu_result)
  );

  comparator _execute_comparator (
    .src_a(rs1_data),
    .src_b(rs2_data),
    .sngd(ctrl.branch_sgnd),
    .branch_flags(branch_flags)
  );

  branch_logic _execute_branch_logic (
    .flow(ctrl.flow),
    .flags(branch_flags),
    .funct3(branch_funct3),
    .pc_src(pc_src)
  );

  logic _unused_ctrl;
  assign _unused_ctrl = |{
    ctrl.reg_write_en,
    ctrl.mem_write_en,
    ctrl.imm_format,
    ctrl.execute_result,
    ctrl.writeback_result,
    ctrl.pc_src,
    ctrl.mem_size,
    ctrl.mem_unsigned,
    ctrl.clear_pc_lsb,
    ctrl.trap,
    ctrl.csr,
    ctrl.system
  };

endmodule
