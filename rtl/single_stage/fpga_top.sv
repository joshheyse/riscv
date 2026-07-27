// fpga_top.sv — board-level top for the single-stage (single-cycle) RISC-V core.
//
// Boilerplate only: ports are declared, nothing is implemented yet.
// Intended contents (see the book's rvsingle chapter):
//   - reset synchronizer / PLL or MMCM for the core clock
//   - single-cycle core instance (rvsingle)
//   - instruction + data memory (BRAM)
//   - simple peripherals (LEDs, switches, UART)
//
// Keep board concerns here rather than inside the core:
//
//   board clock/reset/pins -> fpga_top -> portable core
//   core MMIO/debug state  -> fpga_top -> LEDs/UART/etc.
//
// The portable core should not know which FPGA board, reset polarity, LED
// width, or UART pins are being used.

`timescale 1ns / 1ps

// TODO: remove the lint waivers once every port and parameter is actually used.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
module fpga_top #(
  // Board oscillator frequency, in Hz.
  parameter int unsigned ClkHz = 100_000_000,
  // Width of the board's LED / switch banks.
  parameter int unsigned NumLeds = 8,
  parameter int unsigned NumSwitches = 8
) (
  // Clock and active-low reset from the board.
  input logic clk,
  input logic rst_n,

  // GPIO
  input  logic [NumSwitches-1:0] sw,
  output logic [    NumLeds-1:0] led,

  // UART (115200 8N1, from the FPGA's point of view)
  input  logic uart_rx,
  output logic uart_tx
);
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_on UNUSEDPARAM */

  // TODO: instantiate the single-cycle core, memories, and peripherals here.


  // Placeholder drivers so the design lints and elaborates cleanly.

  assign led = '0;
  assign uart_tx = 1'b1;  // UART idles high



endmodule
