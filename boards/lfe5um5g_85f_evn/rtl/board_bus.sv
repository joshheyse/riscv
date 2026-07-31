`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module board_bus #(
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = "",
  parameter int unsigned NumLeds = board_constants_pkg::NumLeds,
  parameter int unsigned NumDipSwitches = board_constants_pkg::NumDipSwitches,
  parameter int unsigned NumPushButtons = board_constants_pkg::NumPushButtons,
  parameter int unsigned NumGpio = board_constants_pkg::NumGpio
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

  input  logic                 mem_write,
  input  riscv_pkg::word_t     mem_addr,
  input  riscv_pkg::word_t     mem_write_data,
  output riscv_pkg::word_t     mem_read_data,
  input  riscv_pkg::mem_size_t mem_size,
  input  logic                 mem_unsigned
);

  logic mmio_selected;

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
  localparam int unsigned WordBits = riscv_pkg::XLEN;

  logic [NumSources-1:0] selected;
  logic [NumSources-1:0] write_enabled;
  logic [(NumSources*WordBits)-1:0] read_data;
  riscv_pkg::word_t dmem_read_data;
  riscv_pkg::word_t dmem_write_data;
  logic [3:0] dmem_write_mask;

  `define READ_DATA(idx) read_data[(idx)*WordBits+:WordBits]

  assign selected[DmemIdx] = ((mem_addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign mmio_selected = |selected[NumSources-1:1];
  assign write_enabled[DmemIdx] = mem_write & selected[DmemIdx] & !mmio_selected;
  assign write_enabled[LedIdx] = mem_write & selected[LedIdx];
  assign write_enabled[DipSwitchIdx] = 1'b0;
  assign write_enabled[PushButtonIdx] = 1'b0;
  assign write_enabled[GpioIdx] = mem_write & selected[GpioIdx];
  assign write_enabled[UartIdx] = mem_write & selected[UartIdx];
  assign write_enabled[TimerIdx] = 1'b0;
  assign write_enabled[SpiIdx] = mem_write & selected[SpiIdx];
  assign write_enabled[I2cIdx] = mem_write & selected[I2cIdx];

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

  dip_switch_mmio #(
    .DipSwitchAddr (board_constants_pkg::DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) dm_i (
    .mem_addr  (mem_addr),
    .selected  (selected[DipSwitchIdx]),
    .read_data (`READ_DATA(DipSwitchIdx)),
    .dip_switch(dip_switch)
  );

  push_button_mmio #(
    .PushButtonAddr(board_constants_pkg::PushButtonAddr),
    .NumPushButtons(NumPushButtons)
  ) pbm_i (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(selected[PushButtonIdx]),
    .read_data(`READ_DATA(PushButtonIdx)),
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
  ) gm_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[GpioIdx]),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected[GpioIdx]),
    .read_data(`READ_DATA(GpioIdx)),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe)
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

  spi_mmio #(
    .DataAddr        (board_constants_pkg::SpiDataAddr),
    .ControlAddr     (board_constants_pkg::SpiControlAddr),
    .StatusAddr      (board_constants_pkg::SpiStatusAddr),
    .ClocksPerHalfBit(SpiClocksPerHalfBit)
  ) sm_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[SpiIdx]),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected[SpiIdx]),
    .read_data(`READ_DATA(SpiIdx)),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n)
  );

  i2c_mmio #(
    .DataAddr   (board_constants_pkg::I2cDataAddr),
    .ControlAddr(board_constants_pkg::I2cControlAddr),
    .StatusAddr (board_constants_pkg::I2cStatusAddr),
    .AddressAddr(board_constants_pkg::I2cAddressAddr),
    .ClocksPerHalfBit(I2cClocksPerHalfBit)
  ) im_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[I2cIdx]),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected[I2cIdx]),
    .read_data(`READ_DATA(I2cIdx)),
    .i2c_sda_in(i2c_sda_in),
    .i2c_sda_drive_low(i2c_sda_drive_low),
    .i2c_scl_in(i2c_scl_in),
    .i2c_scl_drive_low(i2c_scl_drive_low)
  );

  lsu lsu_i (
    .addr(mem_addr),
    .write_data(mem_write_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .read_mem(dmem_read_data),
    .write_mem(dmem_write_data),
    .write_mask(dmem_write_mask),
    .read_data(`READ_DATA(DmemIdx))
  );

  dmem #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) dmem_i (
    .clk(clk),
    .rst(rst),
    .mem_write(write_enabled[DmemIdx]),
    .addr(mem_addr),
    .write_data(dmem_write_data),
    .write_mask(dmem_write_mask),
    .read_data(dmem_read_data)
  );

  `undef READ_DATA

endmodule
