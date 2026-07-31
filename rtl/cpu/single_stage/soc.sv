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

  logic dbus_write;
  logic dbus_valid;
  logic dbus_ready;
  logic imem_en;
  riscv_pkg::word_t dbus_addr;
  riscv_pkg::word_t dbus_write_data;
  riscv_pkg::word_t dbus_read_data;
  riscv_pkg::mem_size_t dbus_size;
  riscv_pkg::word_t read_mem;
  riscv_pkg::word_t write_mem;
  logic dbus_unsigned;
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
    .dbus_valid(dbus_valid),
    .dbus_write(dbus_write),
    .dbus_addr(dbus_addr),
    .dbus_write_data(dbus_write_data),
    .dbus_read_data(dbus_read_data),
    .dbus_ready(dbus_ready),
    .dbus_size(dbus_size),
    .dbus_unsigned(dbus_unsigned),
    .imem_en(imem_en)
  );

  lsu lsu_i (
    .addr(dbus_addr),
    .write_data(dbus_write_data),
    .mem_size(dbus_size),
    .mem_unsigned(dbus_unsigned),
    .read_data(dbus_read_data),
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
    .mem_valid(dbus_valid),
    .mem_write(dbus_write),
    .addr(dbus_addr),
    .write_data(write_mem),
    .read_data(read_mem),
    .mem_ready(dbus_ready),
    .write_mask(write_mask)
  );

endmodule
