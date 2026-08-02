`timescale 1ns / 1ps

// Minimal pipelined SoC wrapper.
//
// This preserves the original "core + instruction ROM + data RAM" integration
// while keeping memory outside the CPU core. Board-specific wrappers can replace
// the private data RAM with memory-mapped peripherals without changing the
// processor interface.
//
// The wrapper is mainly useful for core-level simulation and simple integration
// tests. Real board tops instantiate `core`, `imem`, and `board_bus` directly so
// the same CPU can run against RAM, MMIO, or simulated halt devices.
//
module soc
  import riscv_pkg::*;
#(
  parameter int unsigned ImemDepthWords = 512,
  parameter              ImemInitFile   = "",
  parameter int unsigned DmemDepthWords = 512,
  parameter              DmemInitFile   = ""
) (
  input logic clk,
  input logic rst,

  output pc_t    pc,
  output pc_t    imem_addr,
  output instr_u instr,
  output logic   halted
);

  // word_t       _dmem_read_data;
  // word_t       _dmem_write_data;
  // logic  [3:0] _write_mask;
  dbus_if _dbus ();
  ibus_if _ibus ();

  assign instr = _ibus.rsp.instr;
  assign imem_addr = _ibus.req.addr;

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) _imem (
    .clk (clk),
    .rst (rst),
    .ibus(_ibus)
  );

  core _core (
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .halted(halted),
    .dbus(_dbus),
    .ibus(_ibus)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem_valid(_dbus.req.valid),
    .mem_write_en(_dbus.req.write_en),
    .mem_addr(_dbus.req.addr),
    .mem_write_data(_dbus.req.write_data),
    .mem_read_data(_dbus.rsp.read_data),
    .mem_ready(_dbus.rsp.ready),
    .mem_write_mask(_dbus.req.write_mask)
  );

endmodule
