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

  logic _imem_en;
  word_t _read_mem;
  word_t _write_mem;
  logic [3:0] _write_mask;
  dbus_if _dbus ();

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) _imem (
    .clk(clk),
    .rst(rst),
    .en(_imem_en),
    .addr(imem_addr),
    .instr(instr.raw)
  );

  core _core (
    .clk(clk),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .imem_addr(imem_addr),
    .halted(halted),
    .dbus(_dbus),
    .imem_en(_imem_en)
  );

  lsu _lsu (
    .addr(_dbus.addr),
    .write_data(_dbus.write_data),
    .mem_size(_dbus.size),
    .mem_unsigned(_dbus.mem_unsigned),
    .read_data(_dbus.read_data),
    .write_mem(_write_mem),
    .read_mem(_read_mem),
    .write_mask(_write_mask)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem_valid(_dbus.valid),
    .mem_write_en(_dbus.write_en),
    .addr(_dbus.addr),
    .write_data(_write_mem),
    .read_data(_read_mem),
    .mem_ready(_dbus.ready),
    .write_mask(_write_mask)
  );

endmodule
