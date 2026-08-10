`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module board_bus
  import riscv_pkg::*;
#(
  parameter int unsigned DmemDepthWords = 512,
  parameter              DmemInitFile   = "",
  parameter int unsigned NumLeds        = board_constants_pkg::NumLeds,
  parameter int unsigned NumDipSwitches = board_constants_pkg::NumDipSwitches,
  parameter int unsigned NumPushButtons = board_constants_pkg::NumPushButtons,
  parameter int unsigned NumGpio        = board_constants_pkg::NumGpio
) (
  input  logic                               clk,
  input  logic                               rst,
  output logic          [       NumLeds-1:0] led,
  input  logic          [NumDipSwitches-1:0] dip_switch,
  input  logic          [NumPushButtons-1:0] push_button,
         uart_if.source                      uart,
         spi_if.source                       spi,
         i2c_if.source                       i2c,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe,

  dbus_if.slave dbus,
  irq_if.source irq
);
  mem_if _dbus_mem ();

  irq_if _clint_irq ();
  irq_if _uart_irq ();
  irq_if _dip_switch_irq ();
  localparam int unsigned UartClocksPerBit = board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;
  localparam int unsigned SpiClocksPerHalfBit = board_constants_pkg::ClockHz / (2 * board_constants_pkg::SpiHz);
  localparam int unsigned I2cClocksPerHalfBit = board_constants_pkg::ClockHz / (2 * board_constants_pkg::I2cHz);

  localparam int unsigned DmemIdx = 0;
  localparam int unsigned LedIdx = 1;
  localparam int unsigned DipSwitchIdx = 2;
  localparam int unsigned PushButtonIdx = 3;
  localparam int unsigned GpioIdx = 4;
  localparam int unsigned UartIdx = 5;
  localparam int unsigned TimerIdx = 6;
  localparam int unsigned SpiIdx = 7;
  localparam int unsigned I2cIdx = 8;
  localparam int unsigned ClintIdx = 9;
  localparam int unsigned NumSources = 10;

  logic [NumSources-1:0] _periph_selected;
  logic [NumSources-1:0] _source_selected;
  localparam int unsigned MeipSources = 3;
  localparam int unsigned MtipSources = 3;
  localparam int unsigned MsipSources = 3;
  localparam int unsigned MEIP_SRC_CLINT      = 0;
  localparam int unsigned MEIP_SRC_UART       = 1;
  localparam int unsigned MEIP_SRC_DIP_SWITCH = 2;
  localparam int unsigned MTIP_SRC_CLINT      = 0;
  localparam int unsigned MSIP_SRC_CLINT      = 0;

  logic [MeipSources-1:0] _meip_sources;
  logic [MtipSources-1:0] _mtip_sources;
  logic [MsipSources-1:0] _msip_sources;


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
          start_addr: board_constants_pkg::DipSwitchAddr,
          end_addr: board_constants_pkg::DipSwitchIrqPendingAddr + 4,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::PushButtonAddr,
          end_addr: board_constants_pkg::PushButtonAddr + 4,
          writeable: 1'b0
      },
      '{
          start_addr: board_constants_pkg::GpioDataInAddr,
          end_addr: board_constants_pkg::GpioToggleAddr + 4,
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
          start_addr: board_constants_pkg::SpiDataAddr,
          end_addr: board_constants_pkg::SpiStatusAddr + 4,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::I2cDataAddr,
          end_addr: board_constants_pkg::I2cStatusAddr + 4,
          writeable: 1'b1
      },
      '{
          start_addr: board_constants_pkg::ClintMsipAddr,
          end_addr: board_constants_pkg::ClintMtimeHiAddr + 4,
          writeable: 1'b1
      }
  };

  mem_if _mmio_mem[NumSources] ();

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

  always_comb begin
    _meip_sources = '0;
    _mtip_sources = '0;
    _msip_sources = '0;

    _meip_sources[MEIP_SRC_CLINT]      = _clint_irq.pending.meip;
    _meip_sources[MEIP_SRC_UART]       = _uart_irq.pending.meip;
    _meip_sources[MEIP_SRC_DIP_SWITCH] = _dip_switch_irq.pending.meip;
    _mtip_sources[MTIP_SRC_CLINT]      = _clint_irq.pending.mtip;
    _msip_sources[MSIP_SRC_CLINT]      = _clint_irq.pending.msip;
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
    assert (_periph_selected[LedIdx] == _source_selected[LedIdx]);
    assert (_periph_selected[DipSwitchIdx] == _source_selected[DipSwitchIdx]);
    assert (_periph_selected[PushButtonIdx] == _source_selected[PushButtonIdx]);
    assert (_periph_selected[GpioIdx] == _source_selected[GpioIdx]);
    assert (_periph_selected[UartIdx] == _source_selected[UartIdx]);
    assert (_periph_selected[TimerIdx] == _source_selected[TimerIdx]);
    assert (_periph_selected[SpiIdx] == _source_selected[SpiIdx]);
    assert (_periph_selected[I2cIdx] == _source_selected[I2cIdx]);
    assert (_periph_selected[ClintIdx] == _source_selected[ClintIdx]);
  end

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) _led_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[LedIdx]),
    .selected(_periph_selected[LedIdx]),
    .led(led)
  );

  dip_switch_mmio #(
    .DipSwitchAddr(board_constants_pkg::DipSwitchAddr),
    .IrqEnableAddr(board_constants_pkg::DipSwitchIrqEnableAddr),
    .IrqPendingAddr(board_constants_pkg::DipSwitchIrqPendingAddr),
    .NumDipSwitches(NumDipSwitches)
  ) _dip_switch_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[DipSwitchIdx]),
    .selected(_periph_selected[DipSwitchIdx]),
    .dip_switch(dip_switch),
    .irq(_dip_switch_irq)
  );

  push_button_mmio #(
    .PushButtonAddr(board_constants_pkg::PushButtonAddr),
    .NumPushButtons(NumPushButtons)
  ) _push_button_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[PushButtonIdx]),
    .selected(_periph_selected[PushButtonIdx]),
    .push_button(push_button)
  );

  gpio_mmio #(
    .GpioDataInAddr(board_constants_pkg::GpioDataInAddr),
    .GpioDataOutAddr(board_constants_pkg::GpioDataOutAddr),
    .GpioDirAddr(board_constants_pkg::GpioDirAddr),
    .GpioSetAddr(board_constants_pkg::GpioSetAddr),
    .GpioClearAddr(board_constants_pkg::GpioClearAddr),
    .GpioToggleAddr(board_constants_pkg::GpioToggleAddr),
    .NumGpio(board_constants_pkg::NumGpio)
  ) _gpio_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[GpioIdx]),
    .selected(_periph_selected[GpioIdx]),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe)
  );

  timer_mmio #(
    .TimerLoAddr(board_constants_pkg::TimerLoAddr),
    .TimerHiAddr(board_constants_pkg::TimerHiAddr)
  ) _timer_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[TimerIdx]),
    .selected(_periph_selected[TimerIdx])
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
    .selected(_periph_selected[UartIdx]),
    .uart(uart),
    .irq(_uart_irq)
  );

  spi_mmio #(
    .DataAddr(board_constants_pkg::SpiDataAddr),
    .ControlAddr(board_constants_pkg::SpiControlAddr),
    .StatusAddr(board_constants_pkg::SpiStatusAddr),
    .ClocksPerHalfBit(SpiClocksPerHalfBit)
  ) _spi_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[SpiIdx]),
    .selected(_periph_selected[SpiIdx]),
    .spi(spi)
  );

  i2c_mmio #(
    .DataAddr(board_constants_pkg::I2cDataAddr),
    .ControlAddr(board_constants_pkg::I2cControlAddr),
    .StatusAddr(board_constants_pkg::I2cStatusAddr),
    .AddressAddr(board_constants_pkg::I2cAddressAddr),
    .ClocksPerHalfBit(I2cClocksPerHalfBit)
  ) _i2c_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_mmio_mem[I2cIdx]),
    .selected(_periph_selected[I2cIdx]),
    .i2c(i2c)
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
    .selected(_periph_selected[ClintIdx]),
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
