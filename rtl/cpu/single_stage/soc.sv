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
  irq_if _irq ();

  assign instr = _ibus.rsp.instr;
  assign imem_addr = _ibus.req.addr;

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile(ImemInitFile)
  ) _imem (
    .clk(clk),
    .rst(rst),
    .ibus(_ibus)
  );

  core _core (
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .halted(halted),
    .dbus(_dbus),
    .ibus(_ibus),
    .irq(_irq)
  );

  mem_if _dmem_mem ();

  assign _dmem_mem.req = _dbus.req;
  assign _dbus.rsp = _dmem_mem.rsp;

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile(DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem(_dmem_mem)
  );

endmodule
