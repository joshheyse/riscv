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
  output logic                      uart_tx,

  output logic spi_sck,
  output logic spi_mosi,
  input  logic spi_miso,
  output logic spi_cs_n,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe,

  input  logic i2c_sda_in,
  output logic i2c_sda_drive_low,
  input  logic i2c_scl_in,
  output logic i2c_scl_drive_low,

  dbus_if.slave dbus
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
  localparam int unsigned NumSources = 9;
  localparam int unsigned WordBits = XLEN;

  logic  [NumSources-1:0] _selected;
  logic  [NumSources-1:0] _write_en;
  logic  [  WordBits-1:0] _read_data       [NumSources];
  word_t                  _dmem_read_data;
  word_t                  _dmem_write_data;
  logic  [           3:0] _dmem_write_mask;
  logic                   _dmem_ready;

  assign _selected[DmemIdx] = ((dbus.addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign _mmio_selected = |_selected[NumSources-1:1];
  assign dbus.ready = _selected[DmemIdx] ? _dmem_ready : dbus.valid;
  assign _write_en[DmemIdx] = dbus.valid & dbus.write_en & _selected[DmemIdx] & !_mmio_selected;
  assign _write_en[LedIdx] = dbus.valid & dbus.write_en & _selected[LedIdx];
  assign _write_en[DipSwitchIdx] = 1'b0;
  assign _write_en[PushButtonIdx] = 1'b0;
  assign _write_en[GpioIdx] = dbus.valid & dbus.write_en & _selected[GpioIdx];
  assign _write_en[UartIdx] = dbus.valid & dbus.write_en & _selected[UartIdx];
  assign _write_en[TimerIdx] = 1'b0;
  assign _write_en[SpiIdx] = dbus.valid & dbus.write_en & _selected[SpiIdx];
  assign _write_en[I2cIdx] = dbus.valid & dbus.write_en & _selected[I2cIdx];

  onehot_mux #(
    .Width(WordBits),
    .NumInputs(NumSources)
  ) _onehot_mux (
    .selected(_selected),
    .data_in(_read_data),
    .data_out(dbus.read_data)
  );

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) _led_mmio (
    .clk(clk),
    .rst(rst),
    .mem_write_en(_write_en[LedIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[LedIdx]),
    .read_data(_read_data[LedIdx]),
    .led(led)
  );

  dip_switch_mmio #(
    .DipSwitchAddr(board_constants_pkg::DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) _dip_switch_mmio (
    .mem_addr(dbus.addr),
    .selected(_selected[DipSwitchIdx]),
    .read_data(_read_data[DipSwitchIdx]),
    .dip_switch(dip_switch)
  );

  push_button_mmio #(
    .PushButtonAddr(board_constants_pkg::PushButtonAddr),
    .NumPushButtons(NumPushButtons)
  ) _push_button_mmio (
    .clk(clk),
    .rst(rst),
    .mem_addr(dbus.addr),
    .selected(_selected[PushButtonIdx]),
    .read_data(_read_data[PushButtonIdx]),
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
    .mem_write_en(_write_en[GpioIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[GpioIdx]),
    .read_data(_read_data[GpioIdx]),
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
    .mem_addr(dbus.addr),
    .selected(_selected[TimerIdx]),
    .read_data(_read_data[TimerIdx])
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr(board_constants_pkg::UartTxAddr),
    .StatusAddr(board_constants_pkg::UartStatusAddr)
  ) _uart_mmio (
    .clk(clk),
    .rst(rst),
    .mem_write_en(_write_en[UartIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[UartIdx]),
    .read_data(_read_data[UartIdx]),
    .tx(uart_tx)
  );

  spi_mmio #(
    .DataAddr(board_constants_pkg::SpiDataAddr),
    .ControlAddr(board_constants_pkg::SpiControlAddr),
    .StatusAddr(board_constants_pkg::SpiStatusAddr),
    .ClocksPerHalfBit(SpiClocksPerHalfBit)
  ) _spi_mmio (
    .clk(clk),
    .rst(rst),
    .mem_write_en(_write_en[SpiIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[SpiIdx]),
    .read_data(_read_data[SpiIdx]),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n)
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
    .mem_write_en(_write_en[I2cIdx]),
    .mem_addr(dbus.addr),
    .mem_write_data(dbus.write_data),
    .selected(_selected[I2cIdx]),
    .read_data(_read_data[I2cIdx]),
    .i2c_sda_in(i2c_sda_in),
    .i2c_sda_drive_low(i2c_sda_drive_low),
    .i2c_scl_in(i2c_scl_in),
    .i2c_scl_drive_low(i2c_scl_drive_low)
  );

  lsu _lsu (
    .addr(dbus.addr),
    .write_data(dbus.write_data),
    .mem_size(dbus.size),
    .mem_unsigned(dbus.mem_unsigned),
    .mem_read_data(_dmem_read_data),
    .mem_write_data(_dmem_write_data),
    .write_mask(_dmem_write_mask),
    .read_data(_read_data[DmemIdx])
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile(DmemInitFile)
  ) _dmem (
    .clk(clk),
    .rst(rst),
    .mem_valid(dbus.valid & _selected[DmemIdx] & !_mmio_selected),
    .mem_write_en(_write_en[DmemIdx]),
    .addr(dbus.addr),
    .write_data(_dmem_write_data),
    .write_mask(_dmem_write_mask),
    .mem_ready(_dmem_ready),
    .read_data(_dmem_read_data)
  );

endmodule
