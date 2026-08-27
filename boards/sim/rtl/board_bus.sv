`timescale 1ns / 1ps

// Simulation platform bus.
//
// This is intentionally smaller than a physical board bus. The simulated
// platform currently models unified memory plus devices that the host harness
// observes directly: LEDs, UART TX, and a free-running timer.
module board_bus
  import riscv_pkg::*;
#(
  parameter int unsigned MemDepthWords = 1024,
  parameter              MemInitFile   = "",
  parameter int unsigned NumLeds       = board_constants_pkg::NumLeds
) (
  input  logic                        clk,
  input  logic                        rst,
  output logic          [NumLeds-1:0] led,
  output dword_t                      time_value,
         uart_if.source               uart,

  mem_if.slave  mem,
  irq_if.source irq
);


  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;

  mem_if _dbus_mem (
    clk,
    rst
  );
  irq_if _uart_irq ();
  irq_if _clint_irq ();
  irq_if _plic_irq ();
  irq_if _plic_sources[3:1] ();
  logic _led_selected;
  logic _timer_selected;
  logic _uart_selected;
  logic _clint_selected;
  logic _plic_selected;
  localparam int unsigned MeipSources = 2;
  localparam int unsigned MtipSources = 2;
  localparam int unsigned MsipSources = 2;
  localparam int unsigned MEIP_SRC_CLINT = 0;
  localparam int unsigned MEIP_SRC_PLIC = 1;
  localparam int unsigned MTIP_SRC_CLINT = 0;
  localparam int unsigned MSIP_SRC_CLINT = 0;

  logic [MeipSources-1:0] _meip_sources;
  logic [MtipSources-1:0] _mtip_sources;
  logic [MsipSources-1:0] _msip_sources;

  localparam int unsigned MemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned UartIdx = 2;
  localparam int unsigned TimerIdx = 3;
  localparam int unsigned ClintIdx = 4;
  localparam int unsigned PlicIdx = 5;
  localparam int unsigned NumSources = 6;

  localparam mmio_source_t _source_map[NumSources] = '{
      '{
          start_addr: board_constants_pkg::MemBase,
          end_addr: board_constants_pkg::MemBase + mem_addr_t'(MemDepthWords * 4),
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
      },
      '{
          start_addr: board_constants_pkg::PlicBase,
          end_addr: board_constants_pkg::PlicMClaimCompleteAddr + 4,
          writeable: 1'b1
      }
  };

  mem_if _mmio_mem[NumSources] (
    clk,
    rst
  );
  logic [NumSources-1:0] _source_selected;

  mmio_router #(
    .NumSources(NumSources),
    .MemIdx(MemIdx),
    .MemHasPrio(1'b1),
    .SourceMap(_source_map)
  ) _mmio_router (
    .clk(clk),
    .rst(rst),
    .dbus(_dbus_mem),
    .selected(_source_selected),
    .mem(_mmio_mem)
  );

  // Straight pass-through, acceptance included: the router decides when it
  // can take a request, and the master upstream must see that answer.
  assign _dbus_mem.req = mem.req;
  assign mem.req_ready = _dbus_mem.req_ready;
  assign _dbus_mem.rsp_ready = mem.rsp_ready;
  assign mem.rsp.valid = _dbus_mem.rsp.valid;
  assign mem.rsp.read_data = _dbus_mem.rsp.read_data;

  always_comb begin
    _meip_sources = '0;
    _mtip_sources = '0;
    _msip_sources = '0;

    _meip_sources[MEIP_SRC_CLINT] = _clint_irq.pending.meip;
    _mtip_sources[MTIP_SRC_CLINT] = _clint_irq.pending.mtip;
    _meip_sources[MEIP_SRC_PLIC] = _plic_irq.pending.meip;
    _msip_sources[MSIP_SRC_CLINT] = _clint_irq.pending.msip;
  end

  irq_aggregator #(
    .N($bits(_meip_sources))
  ) _irq_aggregator (
    .meip_src(_meip_sources),
    .msip_src(_msip_sources),
    .mtip_src(_mtip_sources),
    .irq(irq)
  );

  always_comb begin
    assert ($onehot0(_source_selected));
    assert (_source_selected[LedIdx] == _led_selected);
    assert (_source_selected[TimerIdx] == _timer_selected);
    assert (_source_selected[UartIdx] == _uart_selected);
    assert (_source_selected[ClintIdx] == _clint_selected);
    assert ((_source_selected[PlicIdx] && _dbus_mem.req.valid) == _plic_selected);

    _plic_sources[1].pending = _uart_irq.pending;
    _plic_sources[2].pending = '0;
    _plic_sources[3].pending = '0;
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
    .StatusAddr(board_constants_pkg::UartStatusAddr),
    .IrqEnableAddr(board_constants_pkg::UartIrqEnableAddr)

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
    .time_value(time_value),
    .mem(_mmio_mem[ClintIdx]),
    .selected(_clint_selected),
    .irq(_clint_irq)
  );

  plic #(
    .PlicBase(board_constants_pkg::PlicBase),
    .PlicPriorityBaseAddr(board_constants_pkg::PlicPriorityBaseAddr),
    .PlicPendingAddr(board_constants_pkg::PlicPendingAddr),
    .PlicMEnableAddr(board_constants_pkg::PlicMEnableAddr),
    .PlicMThresholdAddr(board_constants_pkg::PlicMThresholdAddr),
    .PlicMClaimCompleteAddr(board_constants_pkg::PlicMClaimCompleteAddr),
    .NumSources(3),
    .PriorityBits(3)
  ) _plic (
    .clk(clk),
    .rst(rst),
    .selected(_plic_selected),
    .sources(_plic_sources),
    .irq(_plic_irq),
    .mem(_mmio_mem[PlicIdx])
  );

  memory #(
    .DepthWords(MemDepthWords),
    .InitFile(MemInitFile)
  ) _main_memory (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[MemIdx])
  );

endmodule
