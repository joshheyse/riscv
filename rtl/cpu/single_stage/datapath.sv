`timescale 1ns / 1ps

// Single-cycle execution datapath.
//
// This module contains the register file, immediate extender, ALU operand
// muxes, ALU, branch comparator, store-data path, and writeback muxes. The
// controller supplies only selectors and enables; instruction field extraction
// happens here where the register/immediate datapath uses those fields.
//
// ALU operand mux:
//   alu_operands           _src_a      _src_b
//   ----------------  ---------  --------
//   ALU_OPERANDS_RS1_RS2   _rd_data1   _rd_data2
//   ALU_OPERANDS_RS1_IMM   _rd_data1   _imm_ext
//   ALU_OPERANDS_PC_IMM    pc         _imm_ext
//
// Writeback mux:
//   execute_result     pre-memory value
//   -----------------  ----------------
//   EXEC_RESULT_ALU        alu_result
//   EXEC_RESULT_PC_PLUS4   pc + 4
//   EXEC_RESULT_IMM        _imm_ext
//
//   writeback_result         _regfile _wr_data
//   ----------         ----------------
//   WB_RESULT_EXEC         pre-memory value
//   WB_RESULT_MEM         read_data from LSU
//
module datapath
  import riscv_pkg::*;
(
  input logic   clk,
  input instr_u instr,
  input pc_t    pc,

  input logic              reg_write_en,
  input imm_format_t       imm_format,
  input alu_operands_t     alu_operands,
  input execute_result_t   execute_result,
  input alu_op_t           alu_op,
  input writeback_result_t writeback_result,
  input logic              sub_arith,
  input logic              branch_sgnd,
  input mem_data_t         read_data,         // later from dmem/LSU

  output pc_t           ieu_addr,     // branch/jump target
  output alu_data_t     alu_result,   // later dmem address
  output mem_data_t     write_data,   // later store data
  output branch_flags_t branch_flags
);

  reg_data_t _rd_data1;
  reg_data_t _rd_data2;
  reg_data_t _wr_data;
  imm_t      _imm_ext;
  alu_data_t _src_a;
  alu_data_t _src_b;
  reg_data_t _execute_result;

  extend _extend (
    .imm_format(imm_format),
    .instr(instr[31:7]),
    .imm_ext(_imm_ext)
  );

  reg_file _regfile (
    .clk(clk),
    .rd_addr1(instr.r.rs1),
    .rd_addr2(instr.r.rs2),
    .wr_addr(instr.r.rd),
    .wr_data(_wr_data),
    .wr_en(reg_write_en),
    .rd_data1(_rd_data1),
    .rd_data2(_rd_data2)
  );

  comparator _comparator (
    .src_a(_rd_data1),
    .src_b(_rd_data2),
    .sngd(branch_sgnd),
    .branch_flags(branch_flags)
  );

  assign _src_a = alu_operands[1] ? pc : _rd_data1;
  assign _src_b = alu_operands[0] ? _imm_ext : _rd_data2;
  assign write_data = _rd_data2;
  assign ieu_addr = alu_result;

  alu _alu (
    .src_a(_src_a),
    .src_b(_src_b),
    .alu_op(alu_op),
    .sub_arith(sub_arith),
    .alu_result(alu_result)
  );

  execute_result_mux _execute_result_mux (
    .execute_result_kind(execute_result),
    .pc(pc),
    .imm(_imm_ext),
    .alu_result(alu_result),
    .csr_result('0),
    .execute_result(_execute_result)
  );

  writeback_mux _writeback_mux (
    .writeback_result(writeback_result),
    .execute_result(_execute_result),
    .read_data(read_data),
    .writeback_data(_wr_data)
  );

endmodule
