// Generated from boards/lfe5um5g_85f_evn/memmap.yml. Do not edit.
`timescale 1ns / 1ps

package memmap_pkg;
  /* verilator lint_off UNUSEDPARAM */
  localparam logic [31:0] DmemBase = 32'h00000000;
  localparam logic [31:0] DmemSize = 32'h00000800;
  localparam logic [31:0] NumLeds = 32'h00000008;
  localparam logic [31:0] NumDipSwitches = 32'h00000008;
  localparam logic [31:0] NumPushButtons = 32'h00000001;
  localparam logic [31:0] NumGpio = 32'h00000008;
  localparam logic [31:0] LedAddr = 32'h10000000;
  localparam logic [31:0] UartTxAddr = 32'h10001000;
  localparam logic [31:0] UartRxAddr = 32'h10001004;
  localparam logic [31:0] UartControlAddr = 32'h10001008;
  localparam logic [31:0] UartStatusAddr = 32'h1000100c;
  localparam logic [31:0] TimerLoAddr = 32'h10002000;
  localparam logic [31:0] TimerHiAddr = 32'h10002004;
  localparam logic [31:0] DipSwitchAddr = 32'h10003000;
  localparam logic [31:0] PushButtonAddr = 32'h10003004;
  localparam logic [31:0] SpiDataAddr = 32'h10004000;
  localparam logic [31:0] SpiControlAddr = 32'h10004004;
  localparam logic [31:0] SpiStatusAddr = 32'h10004008;
  localparam logic [31:0] SpiClocksPerHalfBit = 32'h00000003;
  localparam logic [31:0] I2cDataAddr = 32'h10005000;
  localparam logic [31:0] I2cAddressAddr = 32'h10005004;
  localparam logic [31:0] I2cControlAddr = 32'h10005008;
  localparam logic [31:0] I2cStatusAddr = 32'h1000500c;
  localparam logic [31:0] GpioDataInAddr = 32'h10006000;
  localparam logic [31:0] GpioDataOutAddr = 32'h10006004;
  localparam logic [31:0] GpioDirAddr = 32'h10006008;
  localparam logic [31:0] GpioSetAddr = 32'h1000600c;
  localparam logic [31:0] GpioClearAddr = 32'h10006010;
  localparam logic [31:0] GpioToggleAddr = 32'h10006014;
  localparam logic [31:0] UartBaud = 32'h0001c200;
  localparam logic [31:0] UartClocksPerBit = 32'h00000068;
  localparam logic [31:0] SimHaltAddr = 32'h1000f000;
  localparam logic [31:0] TimerHz = 32'h00b71b00;
  /* verilator lint_on UNUSEDPARAM */
endpackage
