`timescale 1ns / 1ps

// Integrated control unit.
//
// This module is pure decode/glue:
//   * main_decoder chooses broad datapath controls from opcode
//   * alu_decoder refines the ALU operation from funct3/funct7
//   * branch_logic turns _branch flags + funct3 into PC select
//
// The datapath owns the comparator and supplies `branch_flags`; the controller
// supplies `branch_sgnd` so the comparator can produce the correct `lt` flag.
//
module controller
  import riscv_pkg::*;
(
  input  instr_u        instr,
  input  branch_flags_t branch_flags,
  output control_t      ctrl
);

  logic _branch;
  logic _jump;
  logic _alu_op;
  logic _illegal_main;
  logic _illegal_alu;
  assign ctrl.branch_sgnd   = ~instr.r.funct3.br.unsgnd;
  assign ctrl.illegal_instr = _illegal_main | _illegal_alu;

  main_decoder _main_decoder (
    .instr(instr),
    .reg_write_en(ctrl.reg_write_en),
    .mem_write_en(ctrl.mem_write_en),
    .imm_src(ctrl.imm_src),
    .alu_src(ctrl.alu_src),
    .alu_result_src(ctrl.alu_result_src),
    .result_src(ctrl.result_src),
    .branch(_branch),
    .jump(_jump),
    .alu_op(_alu_op),
    .mem_size(ctrl.mem_size),
    .mem_unsigned(ctrl.mem_unsigned),
    .clear_pc_lsb(ctrl.clear_pc_lsb),
    .illegal_main(_illegal_main)
  );

  branch_logic _branch_logic (
    .branch(_branch),
    .jump(_jump),
    .flags(branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(ctrl.pc_src)
  );

  alu_decoder _alu_decoder (
    .alu_op(_alu_op),
    .instr(instr),
    .alu_select(ctrl.alu_select),
    .sub_arith(ctrl.sub_arith),
    .illegal_alu(_illegal_alu)
  );

endmodule
