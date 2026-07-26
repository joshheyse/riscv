`timescale 1ns / 1ps

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
  output logic branch_sgnd
);

  logic branch;
  logic jump;
  logic alu_op;
  assign branch_sgnd = ~instr.r.funct3.br.unsgnd;

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
    .alu_op(alu_op)
  );

  branch_logic bl (
    .branch(branch),
    .jump  (jump),
    .flags (branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(pc_src)
  );

  alu_decoder alu (
    .alu_op(alu_op),
    .instr(instr),
    .alu_select(alu_select),
    .sub_arith(sub_arith)
  );

endmodule
