`timescale 1ns / 1ps

// Minimal single-stage SoC wrapper.
//
// This preserves the original "core + instruction ROM + data RAM" integration
// while keeping memory outside the CPU core. Board-specific wrappers can extend
// this layer with memory-mapped peripherals without changing the processor.
//
module soc #(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = ""
) (
  input logic clk,
  input logic rst,

  output riscv_pkg::pc_t    pc,
  output riscv_pkg::pc_t    imem_addr,
  output riscv_pkg::instr_u instr,
  output logic halted
);

  logic mem_write;
  logic mem_valid;
  logic mem_ready;
  logic imem_en;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::mem_size_t mem_size;
  riscv_pkg::word_t read_mem;
  riscv_pkg::word_t write_mem;
  logic mem_unsigned;
  logic [3:0] write_mask;

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) imem_i (
    .clk(clk),
    .rst(rst),
    .en(imem_en),
    .addr(imem_addr),
    .instr(instr.raw)
  );

  core core_i (
    .clk(clk),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .imem_addr(imem_addr),
    .halted(halted),
    .mem_valid(mem_valid),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .imem_en(imem_en)
  );

  lsu lsu_i (
    .addr(mem_addr),
    .write_data(mem_write_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .read_data(mem_read_data),
    .write_mem(write_mem),
    .read_mem(read_mem),
    .write_mask(write_mask)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) dmem_i (
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_write(mem_write),
    .addr(mem_addr),
    .write_data(write_mem),
    .read_data(read_mem),
    .mem_ready(mem_ready),
    .write_mask(write_mask)
  );

endmodule
