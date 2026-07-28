`timescale 1ns / 1ps

// Single-cycle RV32I processor core.
//
// This module owns fetch sequencing, decode, execute, branch decision, and
// writeback. Instruction memory and data memory live outside the core so a
// board or SoC wrapper can replace RAM with memory-mapped peripherals.
//
//   IFU.pc -> instruction bus -> instr
//      instr        -> controller -> control bundle
//      instr        -> datapath   -> branch_flags / data address / store data
//      branch_flags -> controller -> pc_src
//      data bus     -> datapath writeback
//
// The `pc` output is both the instruction-memory byte address and a useful
// debug/visibility signal for testbenches and early board bring-up.
//
module core (
  input logic clk,
  input logic rst,

  input riscv_pkg::instr_u instr,
  input riscv_pkg::word_t  mem_read_data,

  output riscv_pkg::pc_t pc,
  output logic mem_write,
  output riscv_pkg::word_t mem_addr,
  output riscv_pkg::word_t mem_write_data,
  output riscv_pkg::mem_size_t mem_size,
  output logic mem_unsigned,
  output logic halted
);

  logic reg_write;
  riscv_pkg::imm_src_t imm_src;
  riscv_pkg::alu_src_t alu_src;
  riscv_pkg::alu_result_src_t alu_result_src;
  riscv_pkg::alu_select_t alu_select;
  riscv_pkg::result_src_t result_src;
  logic sub_arith;
  riscv_pkg::pc_src_t pc_src;
  logic branch_sgnd;
  riscv_pkg::branch_flags_t branch_flags;
  logic clear_pc_lsb;
  riscv_pkg::pc_t raw_ieu_addr;
  riscv_pkg::pc_t ifu_ieu_addr;
  logic halt_now;
  logic illegal_instr;
  logic pc_en;
  logic reg_write_raw;
  logic mem_write_raw;

  assign ifu_ieu_addr = clear_pc_lsb ? {raw_ieu_addr[31:1], 1'b0} : raw_ieu_addr;
  assign halt_now = illegal_instr | halted;
  assign pc_en = !halt_now;
  assign reg_write = reg_write_raw & !halt_now;
  assign mem_write = mem_write_raw & !halt_now;

  always_ff @(posedge clk) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (illegal_instr) begin
      halted <= 1'b1;
    end
  end

  ifu ifu_i (
    .clk(clk),
    .rst(rst),
    .pc_src(pc_src),
    .pc_en(pc_en),
    .ieu_addr(ifu_ieu_addr),
    .pc(pc)
  );

  controller c (
    .instr(instr),
    .branch_flags(branch_flags),
    .reg_write(reg_write_raw),
    .mem_write(mem_write_raw),
    .imm_src(imm_src),
    .alu_src(alu_src),
    .alu_result_src(alu_result_src),
    .alu_select(alu_select),
    .result_src(result_src),
    .sub_arith(sub_arith),
    .pc_src(pc_src),
    .branch_sgnd(branch_sgnd),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .clear_pc_lsb(clear_pc_lsb),
    .illegal_instr(illegal_instr)
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
    .read_data(mem_read_data),
    .ieu_addr(raw_ieu_addr),
    .alu_result(mem_addr),
    .write_data(mem_write_data),
    .branch_flags(branch_flags)
  );

endmodule
