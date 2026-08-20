`timescale 1ns / 1ps

// Minimal pipelined SoC wrapper with one unified instruction/data memory.
// Board-specific wrappers can replace the private RAM with a memory map that
// combines RAM and MMIO without changing the processor interface.
//
module soc
  import riscv_pkg::*;
#(
  parameter int unsigned MemDepthWords = 512,
  parameter              MemInitFile   = "",
  parameter mem_addr_t   CacheableBase = '0,
  parameter mem_addr_t   CacheableEnd  = mem_addr_t'(MemDepthWords * 4)
) (
  input logic clk,
  input logic rst,

  output pc_t  pc,
  output logic halted
);

  mem_if _mem (
    clk,
    rst
  );
  irq_if _irq ();

  assign _irq.pending = '0;

  core #(
    .CacheableBase(CacheableBase),
    .CacheableEnd(CacheableEnd)
  ) _core (
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .halted(halted),
    .mem(_mem),
    .irq(_irq)
  );

  memory #(
    .DepthWords(MemDepthWords),
    .InitFile(MemInitFile)
  ) _mem_storage (
    .clk(clk),
    .rst(rst),
    .mem(_mem)
  );

endmodule
