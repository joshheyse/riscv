`timescale 1ns / 1ps

// Minimal single-stage SoC wrapper.
//
// This preserves the original "core + instruction ROM + data RAM" integration
// while keeping memory outside the CPU core. Board-specific wrappers can extend
// this layer with memory-mapped peripherals without changing the processor.
//
module soc
  import riscv_pkg::*;
#(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = ""
) (
  input logic clk,
  input logic rst,

  output pc_t    pc,
  output pc_t    imem_addr,
  output instr_u instr,
  output logic halted
);

  logic imem_en;
  word_t read_mem;
  word_t write_mem;
  logic [3:0] write_mask;
  dbus_if dbus ();

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
    .dbus(dbus),
    .imem_en(imem_en)
  );

  lsu lsu_i (
    .addr(dbus.addr),
    .write_data(dbus.write_data),
    .mem_size(dbus.size),
    .mem_unsigned(dbus.mem_unsigned),
    .read_data(dbus.read_data),
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
    .mem_valid(dbus.valid),
    .mem_write_en(dbus.write_en),
    .addr(dbus.addr),
    .write_data(write_mem),
    .read_data(read_mem),
    .mem_ready(dbus.ready),
    .write_mask(write_mask)
  );

endmodule
