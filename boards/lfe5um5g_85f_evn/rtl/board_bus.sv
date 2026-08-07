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
  input  logic                      clk,
  input  logic                      rst,
  output logic [       NumLeds-1:0] led,
  input  logic [NumDipSwitches-1:0] dip_switch,
  input  logic [NumPushButtons-1:0] push_button,
  uart_if.source uart,
  spi_if.source spi,
  i2c_if.source i2c,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe,

  dbus_if.slave dbus,
  irq_if.source irq
);

  logic _mmio_selected;

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
  localparam int unsigned WordBits = XLEN;

  logic [NumSources-1:0] _selected;
  logic [NumSources-1:0] _write_en;
  logic [NumSources-1:0] _ready;
  logic [  WordBits-1:0] _read_data[NumSources];
  mem_if _dmem_mem ();
  mem_if _led_mem ();
  mem_if _dip_switch_mem ();
  mem_if _push_button_mem ();
  mem_if _gpio_mem ();
  mem_if _timer_mem ();
  mem_if _uart_mem ();
  mem_if _spi_mem ();
  mem_if _i2c_mem ();
  mem_if _clint_mem ();

  assign _selected[DmemIdx] = ((dbus.req.addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign _mmio_selected = |_selected[NumSources-1:1];
  assign _write_en[DmemIdx] = dbus.req.valid & dbus.req.write_en & _selected[DmemIdx] & !_mmio_selected;
  assign _write_en[LedIdx] = dbus.req.valid & dbus.req.write_en & _selected[LedIdx];
  assign _write_en[DipSwitchIdx] = 1'b0;
  assign _write_en[PushButtonIdx] = 1'b0;
  assign _write_en[GpioIdx] = dbus.req.valid & dbus.req.write_en & _selected[GpioIdx];
  assign _write_en[UartIdx] = dbus.req.valid & dbus.req.write_en & _selected[UartIdx];
  assign _write_en[TimerIdx] = 1'b0;
  assign _write_en[SpiIdx] = dbus.req.valid & dbus.req.write_en & _selected[SpiIdx];
  assign _write_en[I2cIdx] = dbus.req.valid & dbus.req.write_en & _selected[I2cIdx];
  assign _write_en[ClintIdx] = dbus.req.valid & dbus.req.write_en & _selected[ClintIdx];
  assign dbus.rsp.ready = (|_selected) ? |(_selected & _ready) : dbus.req.valid;

  assign _ready[DmemIdx] = _dmem_mem.rsp.ready;
  assign _ready[LedIdx] = _led_mem.rsp.ready;
  assign _ready[DipSwitchIdx] = _dip_switch_mem.rsp.ready;
  assign _ready[PushButtonIdx] = _push_button_mem.rsp.ready;
  assign _ready[GpioIdx] = _gpio_mem.rsp.ready;
  assign _ready[TimerIdx] = _timer_mem.rsp.ready;
  assign _ready[UartIdx] = _uart_mem.rsp.ready;
  assign _ready[SpiIdx] = _spi_mem.rsp.ready;
  assign _ready[I2cIdx] = _i2c_mem.rsp.ready;
  assign _ready[ClintIdx] = _clint_mem.rsp.ready;

  assign _read_data[DmemIdx] = _dmem_mem.rsp.read_data;
  assign _read_data[LedIdx] = _led_mem.rsp.read_data;
  assign _read_data[DipSwitchIdx] = _dip_switch_mem.rsp.read_data;
  assign _read_data[PushButtonIdx] = _push_button_mem.rsp.read_data;
  assign _read_data[GpioIdx] = _gpio_mem.rsp.read_data;
  assign _read_data[TimerIdx] = _timer_mem.rsp.read_data;
  assign _read_data[UartIdx] = _uart_mem.rsp.read_data;
  assign _read_data[SpiIdx] = _spi_mem.rsp.read_data;
  assign _read_data[I2cIdx] = _i2c_mem.rsp.read_data;
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
  assign _dip_switch_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[DipSwitchIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _push_button_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[PushButtonIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _gpio_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[GpioIdx],
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
  assign _uart_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[UartIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _spi_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[SpiIdx],
          addr: dbus.req.addr,
          write_data: dbus.req.write_data,
          write_mask: dbus.req.write_mask
      };
  assign _i2c_mem.req = '{
          valid: dbus.req.valid,
          write_en: _write_en[I2cIdx],
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

  dip_switch_mmio #(
    .DipSwitchAddr(board_constants_pkg::DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) _dip_switch_mmio (
    .mem(_dip_switch_mem),
    .selected(_selected[DipSwitchIdx]),
    .dip_switch(dip_switch)
  );

  push_button_mmio #(
    .PushButtonAddr(board_constants_pkg::PushButtonAddr),
    .NumPushButtons(NumPushButtons)
  ) _push_button_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_push_button_mem),
    .selected(_selected[PushButtonIdx]),
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
    .mem(_gpio_mem),
    .selected(_selected[GpioIdx]),
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
    .uart(uart)
  );

  spi_mmio #(
    .DataAddr(board_constants_pkg::SpiDataAddr),
    .ControlAddr(board_constants_pkg::SpiControlAddr),
    .StatusAddr(board_constants_pkg::SpiStatusAddr),
    .ClocksPerHalfBit(SpiClocksPerHalfBit)
  ) _spi_mmio (
    .clk(clk),
    .rst(rst),
    .mem(_spi_mem),
    .selected(_selected[SpiIdx]),
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
    .mem(_i2c_mem),
    .selected(_selected[I2cIdx]),
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
