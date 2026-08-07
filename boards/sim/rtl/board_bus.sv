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
  input  logic                        clk,
  input  logic                        rst,
  output logic          [NumLeds-1:0] led,
         uart_if.source               uart,

  dbus_if.slave dbus,
  irq_if.source irq
);

  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;

  mem_if _dbus_mem ();
  irq_if _uart_irq ();
  irq_if _clint_irq ();
  logic       _led_selected;
  logic       _timer_selected;
  logic       _uart_selected;
  logic       _clint_selected;
  logic [1:0] _meip_sources;
  logic [1:0] _mtip_sources;

  localparam int unsigned DmemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned UartIdx = 2;
  localparam int unsigned TimerIdx = 3;
  localparam int unsigned ClintIdx = 4;
  localparam int unsigned NumSources = 5;

  localparam mmio_source_t _source_map[NumSources] = '{
      '{
          start_addr: board_constants_pkg::DmemBase,
          end_addr: board_constants_pkg::DmemBase + board_constants_pkg::DmemSize,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::LedAddr,
          end_addr: board_constants_pkg::LedAddr + 4,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::UartTxAddr,
          end_addr: board_constants_pkg::UartStatusAddr + 4,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::TimerLoAddr,
          end_addr: board_constants_pkg::TimerHiAddr + 4,
          writeable: 1'b0
      },
      '{
          start_addr: board_constants_pkg::ClintMsipAddr,
          end_addr: board_constants_pkg::ClintMtimeHiAddr + 4,
          writeable: 1'b1
      }
  };

  mem_if _mmio_mem[NumSources] ();
  logic [NumSources-1:0] _source_selected;

  mmio_router #(
    .NumSources(NumSources),
    .DmemIdx(DmemIdx),
    .DmemHasPrio(1'b1),
    .SourceMap(_source_map)
  ) _mmio_router (
    .dbus(_dbus_mem),
    .selected(_source_selected),
    .mem(_mmio_mem)
  );

  assign _dbus_mem.req = dbus.req;
  assign dbus.rsp.ready = _dbus_mem.rsp.ready;
  assign dbus.rsp.read_data = _dbus_mem.rsp.read_data;

  assign _meip_sources = {_clint_irq.pending.meip, _uart_irq.pending.meip};
  assign _mtip_sources = {_clint_irq.pending.mtip, _uart_irq.pending.mtip};

  irq_aggregator #(
    .N(2)
  ) _irq_aggregator (
    .meip_src(_meip_sources),
    .mtip_src(_mtip_sources),
    .irq(irq)
  );

  always_comb begin
    assert ($onehot0(_source_selected));
    assert (_source_selected[LedIdx] == _led_selected);
    assert (_source_selected[TimerIdx] == _timer_selected);
    assert (_source_selected[UartIdx] == _uart_selected);
    assert (_source_selected[ClintIdx] == _clint_selected);
  end

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) _led_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[LedIdx]),
    .selected(_led_selected),
    .led(led)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) _timer_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[TimerIdx]),
    .selected(_timer_selected)
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr(board_constants_pkg::UartTxAddr),
    .StatusAddr(board_constants_pkg::UartStatusAddr)
  ) _uart_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[UartIdx]),
    .selected(_uart_selected),
    .uart(uart),
    .irq(_uart_irq)
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
    .mem(_mmio_mem[ClintIdx]),
    .selected(_clint_selected),
    .irq(_clint_irq)
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile(DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[DmemIdx])
  );

endmodule
