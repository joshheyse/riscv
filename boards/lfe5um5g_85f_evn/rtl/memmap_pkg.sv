// Generated from boards/lfe5um5g_85f_evn/memmap.yml. Do not edit.
`timescale 1ns / 1ps

package memmap_pkg;
  /* verilator lint_off UNUSEDPARAM */
  localparam logic [31:0] DmemBase = 32'h00000000;
  localparam logic [31:0] DmemSize = 32'h00000800;
  localparam logic [31:0] LedAddr = 32'h10000000;
  localparam logic [31:0] UartTxAddr = 32'h10001000;
  localparam logic [31:0] UartStatusAddr = 32'h10004000;
  localparam logic [31:0] SimHaltAddr = 32'h1000f000;
  localparam logic [31:0] TimerLoAddr = 32'h10002000;
  localparam logic [31:0] TimerHiAddr = 32'h10002004;
  localparam logic [31:0] TimerHz = 32'h00b71b00;
  /* verilator lint_on UNUSEDPARAM */
endpackage
