// Generated from boards/sim/board_constants.yml. Do not edit.
`timescale 1ns / 1ps

package board_constants_pkg;
  /* verilator lint_off UNUSEDPARAM */
  localparam logic [31:0] DmemBase = 32'h00000000;
  localparam logic [31:0] DmemSize = 32'h00000800;
  localparam logic [31:0] NumLeds = 32'h00000008;
  localparam logic [31:0] LedAddr = 32'h10000000;
  localparam logic [31:0] UartTxAddr = 32'h10001000;
  localparam logic [31:0] UartStatusAddr = 32'h1000100c;
  localparam logic [31:0] UartMsipAddr = 32'h10001008;
  localparam logic [31:0] TimerLoAddr = 32'h10002000;
  localparam logic [31:0] TimerHiAddr = 32'h10002004;
  localparam logic [31:0] ClintMsipAddr = 32'h10002008;
  localparam logic [31:0] ClintMtimecmpLoAddr = 32'h10002010;
  localparam logic [31:0] ClintMtimecmpHiAddr = 32'h10002014;
  localparam logic [31:0] ClintMtimeLoAddr = 32'h10002018;
  localparam logic [31:0] ClintMtimeHiAddr = 32'h1000201c;
  localparam logic [31:0] ClockHz = 32'h00b71b00;
  localparam logic [31:0] UartBaud = 32'h0001c200;
  localparam logic [31:0] SimHaltAddr = 32'h1000f000;
  /* verilator lint_on UNUSEDPARAM */
endpackage
