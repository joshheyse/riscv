`timescale 1ns / 1ps

// Integrated control unit.
//
// This module is pure decode/glue:
//   * main_decoder chooses broad datapath controls from opcode
//   * alu_decoder refines the ALU operation from funct3/funct7
//   * branch_logic turns branch flags + funct3 into PC select
//
// The datapath owns the comparator and supplies `branch_flags`; the controller
// supplies `branch_sgnd` so the comparator can produce the correct `lt` flag.
//
module controller
  import riscv_pkg::*;
(
  input instr_u instr,
  input branch_flags_t branch_flags,
  output logic reg_write,
  output logic mem_write,
  output imm_src_t imm_src,
  output alu_src_t alu_src,
  output alu_result_src_t alu_result_src,
  output alu_select_t alu_select,
  output result_src_t result_src,
  output logic sub_arith,
  output pc_src_t pc_src,
  output logic branch_sgnd,
  output mem_size_t mem_size,
  output logic mem_unsigned,
  output logic clear_pc_lsb,
  output logic illegal_instr
);

  logic branch;
  logic jump;
  logic alu_op;
  logic illegal_main;
  logic illegal_alu;
  assign branch_sgnd   = ~instr.r.funct3.br.unsgnd;
  assign illegal_instr = illegal_main | illegal_alu;

  main_decoder md (
    .instr(instr),
    .reg_write(reg_write),
    .mem_write(mem_write),
    .imm_src(imm_src),
    .alu_src(alu_src),
    .alu_result_src(alu_result_src),
    .result_src(result_src),
    .branch(branch),
    .jump(jump),
    .alu_op(alu_op),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .clear_pc_lsb(clear_pc_lsb),
    .illegal_main(illegal_main)
  );

  branch_logic bl (
    .branch(branch),
    .jump  (jump),
    .flags (branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(pc_src)
  );

  alu_decoder ad (
    .alu_op(alu_op),
    .instr(instr),
    .alu_select(alu_select),
    .sub_arith(sub_arith),
    .illegal_alu(illegal_alu)
  );

endmodule
