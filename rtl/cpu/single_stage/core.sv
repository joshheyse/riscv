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
module core
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,
  input instr_u instr,
  output pc_t pc,
  output pc_t imem_addr,
  output logic halted,
  output logic dbus_valid,
  output logic dbus_write_en,
  output word_t dbus_addr,
  output word_t dbus_write_data,
  input word_t dbus_read_data,
  input logic dbus_ready,
  output mem_size_t dbus_size,
  output logic dbus_unsigned,
  output logic imem_en
);

  logic reg_write;
  imm_src_t imm_src;
  alu_src_t alu_src;
  alu_result_src_t alu_result_src;
  alu_select_t alu_select;
  result_src_t result_src;
  logic sub_arith;
  pc_src_t pc_src;
  logic branch_sgnd;
  branch_flags_t branch_flags;
  logic clear_pc_lsb;
  pc_t raw_ieu_addr;
  pc_t ifu_ieu_addr;
  logic halt_now;
  logic illegal_instr;
  logic pc_en;
  logic reg_write_raw;
  logic mem_write_raw;
  logic instr_valid;
  pc_src_t ifu_pc_src;

  logic dbus_pending;
  logic dbus_instr;
  logic dbus_wait;
  logic load_complete;
  logic load_instr;

  assign ifu_ieu_addr = clear_pc_lsb ? {raw_ieu_addr[31:1], 1'b0} : raw_ieu_addr;

  assign halt_now = halted || (illegal_instr && instr_valid);
  assign dbus_instr = load_instr || mem_write_raw;
  assign dbus_valid = instr_valid && dbus_instr && !halt_now && !dbus_pending;
  assign dbus_wait = instr_valid && dbus_instr && !halt_now && !dbus_ready;
  assign pc_en = !halt_now && !dbus_wait;
  assign imem_en = pc_en;
  assign reg_write = reg_write_raw && instr_valid && !halt_now && (!load_instr || load_complete);
  assign dbus_write_en = mem_write_raw && instr_valid && !halt_now;

  assign ifu_pc_src = instr_valid ? pc_src : PC_SRC_INC;

  assign load_instr = result_src == RESULT_MEM;
  assign load_complete = instr_valid && load_instr && dbus_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (illegal_instr & instr_valid) begin
      halted <= 1'b1;
    end
    if (rst || halt_now) begin
      dbus_pending <= 1'b0;
    end else if (dbus_valid && !dbus_ready) begin
      dbus_pending <= 1'b1;
    end else if (dbus_pending && dbus_ready) begin
      dbus_pending <= 1'b0;
    end
  end

  ifu ifu_i (
    .clk(clk),
    .rst(rst),
    .pc_src(ifu_pc_src),
    .pc_en(pc_en),
    .ieu_addr(ifu_ieu_addr),
    .pc(pc),
    .imem_addr(imem_addr),
    .instr_valid(instr_valid)
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
    .mem_size(dbus_size),
    .mem_unsigned(dbus_unsigned),
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
    .read_data(dbus_read_data),
    .ieu_addr(raw_ieu_addr),
    .alu_result(dbus_addr),
    .write_data(dbus_write_data),
    .branch_flags(branch_flags)
  );

endmodule
