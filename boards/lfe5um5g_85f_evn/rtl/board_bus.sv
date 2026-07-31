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

  riscv_pkg::word_t lsu_read_data;
  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t dip_switch_read_data;
  riscv_pkg::word_t push_button_read_data;
  riscv_pkg::word_t gpio_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t timer_read_data;
  riscv_pkg::word_t spi_read_data;
  riscv_pkg::word_t i2c_read_data;
  logic dmem_selected;
  logic led_selected;
  logic dip_switch_selected;
  logic push_button_selected;
  logic gpio_selected;
  logic uart_selected;
  logic timer_selected;
  logic spi_selected;
  logic i2c_selected;
  logic mmio_selected;
  logic dmem_write;
  logic led_write;
  logic gpio_write;
  logic uart_write;
  logic spi_write;
  logic i2c_write;

  localparam int unsigned UartClocksPerBit =
      board_constants_pkg::ClockHz / board_constants_pkg::UartBaud;
  localparam int unsigned SpiClocksPerHalfBit =
      board_constants_pkg::ClockHz / (2 * board_constants_pkg::SpiHz);
  localparam int unsigned I2cClocksPerHalfBit =
      board_constants_pkg::ClockHz / (2 * board_constants_pkg::I2cHz);

  assign dmem_selected = ((mem_addr - board_constants_pkg::DmemBase) < board_constants_pkg::DmemSize);
  assign mmio_selected = led_selected | uart_selected | timer_selected | dip_switch_selected | push_button_selected | spi_selected | gpio_selected | i2c_selected;
  assign dmem_write = mem_write & dmem_selected & !mmio_selected;
  assign led_write = mem_write & led_selected;
  assign gpio_write = mem_write & gpio_selected;
  assign uart_write = mem_write & uart_selected;
  assign spi_write = mem_write & spi_selected;
  assign i2c_write = mem_write & i2c_selected;

  always_comb begin
    mem_read_data = '0;

    if (led_selected) begin
      mem_read_data = led_read_data;
    end else if (dip_switch_selected) begin
      mem_read_data = dip_switch_read_data;
    end else if (push_button_selected) begin
      mem_read_data = push_button_read_data;
    end else if (gpio_selected) begin
      mem_read_data = gpio_read_data;
    end else if (uart_selected) begin
      mem_read_data = uart_read_data;
    end else if (timer_selected) begin
      mem_read_data = timer_read_data;
    end else if (spi_selected) begin
      mem_read_data = spi_read_data;
    end else if (i2c_selected) begin
      mem_read_data = i2c_read_data;
    end else if (dmem_selected) begin
      mem_read_data = lsu_read_data;
    end
  end

  led_mmio #(
    .LedAddr(board_constants_pkg::LedAddr),
    .NumLeds(NumLeds)
  ) lm_i (
    .clk(clk),
    .rst(rst),
    .mem_write(led_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(led_selected),
    .read_data(led_read_data),
    .led(led)
  );

  dip_switch_mmio #(
    .DipSwitchAddr (board_constants_pkg::DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) dm_i (
    .mem_addr  (mem_addr),
    .selected  (dip_switch_selected),
    .read_data (dip_switch_read_data),
    .dip_switch(dip_switch)
  );

  push_button_mmio #(
    .PushButtonAddr(board_constants_pkg::PushButtonAddr),
    .NumPushButtons(NumPushButtons)
  ) pbm_i (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(push_button_selected),
    .read_data(push_button_read_data),
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
    .mem_write(gpio_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(gpio_selected),
    .read_data(gpio_read_data),
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
    .selected(timer_selected),
    .read_data(timer_read_data)
  );

  uart_mmio #(
    .ClocksPerBit(UartClocksPerBit),
    .TxDataAddr  (board_constants_pkg::UartTxAddr),
    .StatusAddr  (board_constants_pkg::UartStatusAddr)
  ) um_i (
    .clk(clk),
    .rst(rst),
    .mem_write(uart_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(uart_selected),
    .read_data(uart_read_data),
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
    .mem_write(spi_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(spi_selected),
    .read_data(spi_read_data),
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
    .mem_write(i2c_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(i2c_selected),
    .read_data(i2c_read_data),
    .i2c_sda_in(i2c_sda_in),
    .i2c_sda_drive_low(i2c_sda_drive_low),
    .i2c_scl_in(i2c_scl_in),
    .i2c_scl_drive_low(i2c_scl_drive_low)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) lsu_i (
    .clk(clk),
    .mem_write(dmem_write),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(lsu_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

endmodule
