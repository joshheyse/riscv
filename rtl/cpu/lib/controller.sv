`timescale 1ns / 1ps

// Integrated control unit.
//
// This module is pure decode/glue:
//   * main_decoder chooses broad datapath controls from opcode
//   * alu_decoder refines the ALU operation from funct3/funct7
//   * branch_logic turns decoded flow + branch flags + funct3 into PC select
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

  logic _alu_decode_en;
  logic _main_op_illegal;
  logic _alu_op_illegal;
  logic _mem_op_illegal;
  logic _csr_op_illegal;
  logic _main_reg_write_en;
  logic _csr_reg_write_en;

  assign ctrl.branch_sgnd = ~instr.r.funct3.br.unsgnd;
  assign ctrl.illegal_instr = _main_op_illegal | _alu_op_illegal | _mem_op_illegal | _csr_op_illegal;

  assign _csr_reg_write_en = ctrl.csr_en && (instr.r.rd != 5'd0);
  assign ctrl.reg_write_en = _main_reg_write_en | _csr_reg_write_en;

  main_decoder _main_decoder (
    .instr(instr),
    .reg_write_en(_main_reg_write_en),
    .mem_write_en(ctrl.mem_write_en),
    .imm_format(ctrl.imm_format),
    .alu_operands(ctrl.alu_operands),
    .execute_result(ctrl.execute_result),
    .writeback_result(ctrl.writeback_result),
    .flow(ctrl.flow),
    .alu_decode_en(_alu_decode_en),
    .clear_pc_lsb(ctrl.clear_pc_lsb),
    .main_op_illegal(_main_op_illegal)
  );

  branch_logic _branch_logic (
    .flow(ctrl.flow),
    .flags(branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(ctrl.pc_src)
  );

  alu_decoder _alu_decoder (
    .alu_decode_en(_alu_decode_en),
    .instr(instr),
    .alu_op(ctrl.alu_op),
    .sub_arith(ctrl.sub_arith),
    .alu_op_illegal(_alu_op_illegal)
  );

  mem_decoder _mem_decoder (
    .instr(instr),
    .mem_size(ctrl.mem_size),
    .mem_unsigned(ctrl.mem_unsigned),
    .mem_op_illegal(_mem_op_illegal)
  );

  csr_decoder _csr_decoder (
    .instr(instr),
    .csr_en(ctrl.csr_en),
    .csr_write_en(ctrl.csr_write_en),
    .csr_op(ctrl.csr_op),
    .csr_use_zimm(ctrl.csr_use_zimm),
    .csr_op_illegal(_csr_op_illegal)
  );

endmodule
