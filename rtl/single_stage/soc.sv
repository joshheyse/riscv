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
  output riscv_pkg::instr_u instr,
  output logic halted
);

  logic mem_write;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::mem_size_t mem_size;
  logic mem_unsigned;

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) imem_i (
    .addr (pc),
    .instr(instr.raw)
  );

  core core_i (
    .clk(clk),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .halted(halted)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) lsu_i (
    .clk(clk),
    .mem_write(mem_write),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

endmodule
