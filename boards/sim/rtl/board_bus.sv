`timescale 1ns / 1ps

// Simulation platform bus.
//
// This is intentionally smaller than a physical board bus. The simulated
// platform currently models only data memory plus devices that the host harness
// observes directly: LEDs, UART TX, and a free-running timer.
module board_bus #(
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = "",
  parameter int unsigned NumLeds = board_constants_pkg::NumLeds
) (
  input  logic               clk,
  input  logic               rst,
  output logic [NumLeds-1:0] led,
  output logic               uart_tx,

  input  logic                 mem_write,
  input  riscv_pkg::word_t     mem_addr,
  input  riscv_pkg::word_t     mem_write_data,
  output riscv_pkg::word_t     mem_read_data,
  input  riscv_pkg::mem_size_t mem_size,
  input  logic                 mem_unsigned
);

  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;

  logic mmio_selected;

  localparam int unsigned DmemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned UartIdx = 2;
  localparam int unsigned TimerIdx = 3;
  localparam int unsigned NumSources = 4;
  localparam int unsigned WordBits = riscv_pkg::XLEN;

  logic [NumSources-1:0] selected;
  logic [NumSources-1:0] write_enabled;
  logic [(NumSources*WordBits)-1:0] read_data;

  `define READ_DATA(idx) read_data[(idx)*WordBits+:WordBits]

  assign selected[DmemIdx] = ((mem_addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign mmio_selected = |selected[NumSources-1:1];
  assign write_enabled[TimerIdx] = 1'b0;
  assign write_enabled[DmemIdx] = mem_write & selected[DmemIdx] & !mmio_selected;
  assign write_enabled[LedIdx] = mem_write & selected[LedIdx];
  assign write_enabled[UartIdx] = mem_write & selected[UartIdx];

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) om (
    .selected(selected),
    .data_in (read_data),
    .data_out(mem_read_data)
  );

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) lm_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[LedIdx]),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected[LedIdx]),
    .read_data(`READ_DATA(LedIdx)),
    .led(led)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) tm_i (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(selected[TimerIdx]),
    .read_data(`READ_DATA(TimerIdx))
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr  (board_constants_pkg::UartTxAddr),
    .StatusAddr  (board_constants_pkg::UartStatusAddr)
  ) um_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[UartIdx]),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected[UartIdx]),
    .read_data(`READ_DATA(UartIdx)),
    .tx(uart_tx)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) dmem_i (
    .clk(clk),
    .mem_write(write_enabled[DmemIdx]),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(`READ_DATA(DmemIdx)),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

  `undef READ_DATA

endmodule
