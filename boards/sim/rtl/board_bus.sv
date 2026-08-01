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
  parameter              DmemInitFile   = "",
  parameter int unsigned NumLeds        = board_constants_pkg::NumLeds
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
  logic [NumSources-1:0] _write_en;
  logic [NumSources-1:0] _ready;
  logic [  WordBits-1:0] _read_data[NumSources];

  assign _selected[DmemIdx] = ((dbus.req.addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign _mmio_selected = |_selected[NumSources-1:1];
  assign _write_en[TimerIdx] = 1'b0;
  assign _write_en[DmemIdx] = dbus.req.valid & dbus.req.write_en & _selected[DmemIdx] & !_mmio_selected;
  assign _write_en[LedIdx] = dbus.req.valid & dbus.req.write_en & _selected[LedIdx];
  assign _write_en[UartIdx] = dbus.req.valid & dbus.req.write_en & _selected[UartIdx];
  assign dbus.rsp.ready = (|_selected) ? |(_selected & _ready) : dbus.req.valid;

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) _onehot_mux (
    .selected(_selected),
    .data_in(_read_data),
    .data_out(dbus.rsp.read_data)
  );

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) _led_mmio (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.req.valid),
    .mem_write_en(_write_en[LedIdx]),
    .mem_addr(dbus.req.addr),
    .mem_write_data(dbus.req.write_data),
    .mem_write_mask(dbus.req.write_mask),
    .selected(_selected[LedIdx]),
    .mem_ready(_ready[LedIdx]),
    .mem_read_data(_read_data[LedIdx]),
    .led(led)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) _timer_mmio (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.req.valid),
    .mem_write_en(_write_en[TimerIdx]),
    .mem_addr(dbus.req.addr),
    .mem_write_data(dbus.req.write_data),
    .mem_write_mask(dbus.req.write_mask),
    .selected(_selected[TimerIdx]),
    .mem_ready(_ready[TimerIdx]),
    .mem_read_data(_read_data[TimerIdx])
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr(board_constants_pkg::UartTxAddr),
    .StatusAddr(board_constants_pkg::UartStatusAddr)
  ) _uart_mmio (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.req.valid),
    .mem_write_en(_write_en[UartIdx]),
    .mem_addr(dbus.req.addr),
    .mem_write_data(dbus.req.write_data),
    .mem_write_mask(dbus.req.write_mask),
    .selected(_selected[UartIdx]),
    .mem_ready(_ready[UartIdx]),
    .mem_read_data(_read_data[UartIdx]),
    .tx(uart_tx)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile(DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.req.valid & _selected[DmemIdx] & !_mmio_selected),
    .mem_write_en(_write_en[DmemIdx]),
    .mem_addr(dbus.req.addr),
    .mem_write_data(dbus.req.write_data),
    .mem_write_mask(dbus.req.write_mask),
    .mem_ready(_ready[DmemIdx]),
    .mem_read_data(_read_data[DmemIdx])
  );

endmodule
