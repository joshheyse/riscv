`timescale 1ns / 1ps

// Simulation platform bus.
//
// This is intentionally smaller than a physical board bus. The simulated
// platform currently models only data memory plus devices that the host harness
// observes directly: LEDs, UART TX, and a free-running timer.
module board_bus
  import riscv_pkg::*;
#(
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = "",
  parameter int unsigned NumLeds = board_constants_pkg::NumLeds
) (
  input  logic               clk,
  input  logic               rst,
  output logic [NumLeds-1:0] led,
  output logic               uart_tx,

  dbus_if.slave dbus
);

  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;

  logic _mmio_selected;

  localparam int unsigned DmemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned UartIdx = 2;
  localparam int unsigned TimerIdx = 3;
  localparam int unsigned NumSources = 4;
  localparam int unsigned WordBits = XLEN;

  logic [NumSources-1:0] _selected;
  logic [NumSources-1:0] _write_enabled;
  logic [WordBits-1:0] _read_data[NumSources];
  word_t _dmem_read_data;
  word_t _dmem_write_data;
  logic [3:0] _dmem_write_mask;
  logic _dmem_ready;

  assign _selected[DmemIdx] = ((dbus.addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign _mmio_selected = |_selected[NumSources-1:1];
  assign dbus.ready = _selected[DmemIdx] ? _dmem_ready : dbus.valid;
  assign _write_enabled[TimerIdx] = 1'b0;
  assign _write_enabled[DmemIdx] = dbus.valid & dbus.write_en & _selected[DmemIdx] & !_mmio_selected;
  assign _write_enabled[LedIdx] = dbus.valid & dbus.write_en & _selected[LedIdx];
  assign _write_enabled[UartIdx] = dbus.valid & dbus.write_en & _selected[UartIdx];

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) _onehot_mux (
    .selected(_selected),
    .data_in (_read_data),
    .data_out(dbus.read_data)
  );

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) _led_mmio (
    .clk(clk),
    .rst(rst),
    .mem_write_en(_write_enabled[LedIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[LedIdx]),
    .read_data(_read_data[LedIdx]),
    .led(led)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) _timer_mmio (
    .clk(clk),
    .rst(rst),
    .mem_addr(dbus.addr),
    .selected(_selected[TimerIdx]),
    .read_data(_read_data[TimerIdx])
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr  (board_constants_pkg::UartTxAddr),
    .StatusAddr  (board_constants_pkg::UartStatusAddr)
  ) _uart_mmio (
    .clk(clk),
    .rst(rst),
    .mem_write_en(_write_enabled[UartIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[UartIdx]),
    .read_data(_read_data[UartIdx]),
    .tx(uart_tx)
  );

  lsu _lsu (
    .addr(dbus.addr),
    .write_data(dbus.write_data),
    .mem_size(dbus.size),
    .mem_unsigned(dbus.mem_unsigned),
    .read_mem(_dmem_read_data),
    .write_mem(_dmem_write_data),
    .write_mask(_dmem_write_mask),
    .read_data(_read_data[DmemIdx])
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.valid & _selected[DmemIdx] & !_mmio_selected),
    .mem_write_en(_write_enabled[DmemIdx]),
    .addr(dbus.addr),
    .write_data(_dmem_write_data),
    .write_mask(_dmem_write_mask),
    .mem_ready(_dmem_ready),
    .read_data(_dmem_read_data)
  );

endmodule
