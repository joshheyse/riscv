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
  input  instr_u          instr,
  input  branch_flags_t   branch_flags,
  output logic            reg_write,
  output logic            mem_write,
  output imm_src_t        imm_src,
  output alu_src_t        alu_src,
  output alu_result_src_t alu_result_src,
  output alu_select_t     alu_select,
  output result_src_t     result_src,
  output logic            sub_arith,
  output pc_src_t         pc_src,
  output logic            branch_sgnd,
  output mem_size_t       mem_size,
  output logic            mem_unsigned,
  output logic            clear_pc_lsb,
  output logic            illegal_instr
);

  logic _branch;
  logic _jump;
  logic _alu_op;
  logic _illegal_main;
  logic _illegal_alu;
  assign branch_sgnd   = ~instr.r.funct3.br.unsgnd;
  assign illegal_instr = _illegal_main | _illegal_alu;

  main_decoder _main_decoder (
    .instr(instr),
    .reg_write(reg_write),
    .mem_write(mem_write),
    .imm_src(imm_src),
    .alu_src(alu_src),
    .alu_result_src(alu_result_src),
    .result_src(result_src),
    .branch(_branch),
    .jump(_jump),
    .alu_op(_alu_op),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .clear_pc_lsb(clear_pc_lsb),
    .illegal_main(_illegal_main)
  );

  branch_logic _branch_logic (
    .branch(_branch),
    .jump(_jump),
    .flags(branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(pc_src)
  );

  alu_decoder _alu_decoder (
    .alu_op(_alu_op),
    .instr(instr),
    .alu_select(alu_select),
    .sub_arith(sub_arith),
    .illegal_alu(_illegal_alu)
  );

endmodule
