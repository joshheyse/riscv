`timescale 1ns / 1ps

// Single-cycle RV32I core integration.
//
// Current top-level CPU datapath:
//
//   IFU.pc -> imem.addr -> instr
//      instr -> controller -> control bundle
//      instr -> datapath   -> branch_flags / alu_result / write_data
//      branch_flags -> controller -> pc_src
//      alu_result + write_data + mem_write -> LSU -> read_data
//      read_data -> datapath writeback
//
// The public `pc` and `instr` outputs are debug/visibility ports for
// testbenches and early board bring-up.
//
module core
  import riscv_pkg::*;
#(
  parameter int unsigned ImemDepthWords = 512,
  parameter string ImemInitFile = ""
) (
  input logic clk,
  input logic rst,

  output pc_t    pc,
  output instr_u instr
);

  logic reg_write;
  logic mem_write;
  imm_src_t imm_src;
  alu_src_t alu_src;
  alu_result_src_t alu_result_src;
  alu_select_t alu_select;
  result_src_t result_src;
  logic sub_arith;
  pc_src_t pc_src;
  logic branch_sgnd;
  pc_t ieu_addr;
  branch_flags_t branch_flags;
  word_t read_data;
  word_t alu_result;
  word_t write_data;

  ifu ifu_i (
      .clk(clk),
      .rst(rst),
      .pc_src(pc_src),
      .ieu_addr(ieu_addr),
      .pc(pc)
  );

  imem #(
      .DepthWords(ImemDepthWords),
      .InitFile  (ImemInitFile)
  ) imem_i (
      .addr (pc),
      .instr(instr.raw)
  );

  controller c (
      .instr(instr),
      .branch_flags(branch_flags),
      .reg_write(reg_write),
      .mem_write(mem_write),
      .imm_src(imm_src),
      .alu_src(alu_src),
      .alu_result_src(alu_result_src),
      .alu_select(alu_select),
      .result_src(result_src),
      .sub_arith(sub_arith),
      .pc_src(pc_src),
      .branch_sgnd(branch_sgnd)
  );

  datapath d (
      .clk(clk),
      .instr(instr),
      .pc(pc),
      .reg_write(reg_write),
      .imm_src(imm_src),
      .alu_src(alu_src),
      .alu_result_src(alu_result_src),
      .alu_select(alu_select),
      .result_src(result_src),
      .sub_arith(sub_arith),
      .branch_sgnd(branch_sgnd),
      .read_data(read_data),
      .ieu_addr(ieu_addr),
      .alu_result(alu_result),
      .write_data(write_data),
      .branch_flags(branch_flags)
  );

  lsu l (
      .clk(clk),
      .mem_write(mem_write),
      .addr(alu_result),
      .write_data(write_data),
      .read_data(read_data)
  );

endmodule
