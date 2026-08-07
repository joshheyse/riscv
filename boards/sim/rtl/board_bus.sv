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
  input  logic               uart_rx,

  dbus_if.slave dbus,
  irq_if.source irq
);

  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;

  logic _mmio_selected;

  localparam int unsigned DmemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned UartIdx = 2;
  localparam int unsigned TimerIdx = 3;
  localparam int unsigned ClintIdx = 4;
  localparam int unsigned NumSources = 5;
  localparam int unsigned WordBits = XLEN;

  logic [NumSources-1:0] _selected;
  logic [NumSources-1:0] _write_en;
  logic [NumSources-1:0] _ready;
  logic [  WordBits-1:0] _read_data[NumSources];
  mem_if _clint_mem ();
  mem_if _dmem_mem ();
  mem_if _led_mem ();
  mem_if _uart_mem ();
  mem_if _timer_mem ();

  assign _selected[DmemIdx] = ((dbus.req.addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);

  assign _mmio_selected = |_selected[NumSources-1:1];
  assign _write_en[TimerIdx] = 1'b0;
  assign _write_en[DmemIdx] = dbus.req.valid & dbus.req.write_en & _selected[DmemIdx] & !_mmio_selected;
  assign _write_en[LedIdx] = dbus.req.valid & dbus.req.write_en & _selected[LedIdx];
  assign _write_en[UartIdx] = dbus.req.valid & dbus.req.write_en & _selected[UartIdx];
  assign _write_en[ClintIdx] = dbus.req.valid & dbus.req.write_en & _selected[ClintIdx];
  assign dbus.rsp.ready = (|_selected) ? |(_selected & _ready) : dbus.req.valid;

  assign _ready[DmemIdx] = _dmem_mem.rsp.ready;
  assign _ready[LedIdx] = _led_mem.rsp.ready;
  assign _ready[UartIdx] = _uart_mem.rsp.ready;
  assign _ready[TimerIdx] = _timer_mem.rsp.ready;
  assign _ready[ClintIdx] = _clint_mem.rsp.ready;

  assign _read_data[DmemIdx] = _dmem_mem.rsp.read_data;
  assign _read_data[LedIdx] = _led_mem.rsp.read_data;
  assign _read_data[UartIdx] = _uart_mem.rsp.read_data;
  assign _read_data[TimerIdx] = _timer_mem.rsp.read_data;
  assign _read_data[ClintIdx] = _clint_mem.rsp.read_data;

  assign _dmem_mem.req = '{
          valid: dbus.req.valid && _selected[DmemIdx] && !_mmio_selected,
          write_en: _write_en[DmemIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _led_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[LedIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _uart_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[UartIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _timer_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[TimerIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _clint_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[ClintIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };

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
    .mem(_led_mem),
    .selected(_selected[LedIdx]),
    .led(led)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) _timer_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_timer_mem),
    .selected(_selected[TimerIdx])
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr(board_constants_pkg::UartTxAddr),
    .StatusAddr(board_constants_pkg::UartStatusAddr)
  ) _uart_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_uart_mem),
    .selected(_selected[UartIdx]),
    .tx(uart_tx),
    .rx(uart_rx)
  );

  clint #(
    .MsipAddr(board_constants_pkg::ClintMsipAddr),
    .MtimecmpLoAddr(board_constants_pkg::ClintMtimecmpLoAddr),
    .MtimecmpHiAddr(board_constants_pkg::ClintMtimecmpHiAddr),
    .MtimeLoAddr(board_constants_pkg::ClintMtimeLoAddr),
    .MtimeHiAddr(board_constants_pkg::ClintMtimeHiAddr)
  ) _clint (
    .clk(clk),
    .rst(rst),
    .mem(_clint_mem),
    .selected(_selected[ClintIdx]),
    .irq(irq)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile(DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem(_dmem_mem)
  );

endmodule
