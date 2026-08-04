`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module top
  import riscv_pkg::*;
#(
  parameter int unsigned ImemDepthWords     = 512,
  parameter              ImemInitFile       = "",
  parameter int unsigned PowerOnResetCycles = 16,
  parameter int unsigned NumGpio            = board_constants_pkg::NumGpio
) (
  input  logic               clk_12mhz,
  input  logic               rst_n,
  output logic [        7:0] led_n,
  input  logic [        7:0] dip_switch_n,
  input  logic               push_button_n,
  output logic               uart_tx,
  inout  logic [NumGpio-1:0] gpio,
  output logic               spi_sck,
  output logic               spi_mosi,
  input  logic               spi_miso,
  output logic               spi_cs_n,
  inout  logic               i2c_sda,
  inout  logic               i2c_scl
);

  localparam int unsigned ResetCounterBits = $clog2(PowerOnResetCycles + 1);
  localparam logic [ResetCounterBits-1:0] ResetCounterMax = ResetCounterBits'(PowerOnResetCycles);
  localparam logic [ResetCounterBits-1:0] ResetCounterInc = ResetCounterBits'(1);
  /* verilator lint_off PROCASSINIT */
  logic [ResetCounterBits-1:0] _reset_counter = '0;
  /* verilator lint_on PROCASSINIT */

  logic                        _rst;
  logic                        _power_on_rst;
  logic                        _halted;

  dbus_if _dbus ();
  ibus_if _ibus ();

  logic [        7:0] _led;
  logic [        7:0] _dip_switch;
  logic               _push_button;

  logic [NumGpio-1:0] _gpio_in;
  logic [NumGpio-1:0] _gpio_out;
  logic [NumGpio-1:0] _gpio_oe;

  logic               _i2c_sda_in;
  logic               _i2c_sda_drive_low;
  logic               _i2c_scl_in;
  logic               _i2c_scl_drive_low;

  initial begin
    assert (PowerOnResetCycles > 0);
  end

  assign _power_on_rst = (_reset_counter != ResetCounterMax);
  assign _rst = ~rst_n | _power_on_rst;

  assign led_n = _halted ? 8'h00 : ~_led;
  assign _dip_switch = ~dip_switch_n;
  assign _push_button = ~push_button_n;
  assign _gpio_in = gpio;

  assign _i2c_sda_in = i2c_sda;
  assign _i2c_scl_in = i2c_scl;

  assign i2c_sda = _i2c_sda_drive_low ? 1'b0 : 1'bz;
  assign i2c_scl = _i2c_scl_drive_low ? 1'b0 : 1'bz;

  genvar _i;
  generate
    for (_i = 0; _i < NumGpio; _i++) begin : gen_gpio_tristate
      assign gpio[_i] = _gpio_oe[_i] ? _gpio_out[_i] : 1'bz;
    end
  endgenerate

  always_ff @(posedge clk_12mhz) begin
    if (!rst_n) begin
      _reset_counter <= '0;
    end else if (_power_on_rst) begin
      _reset_counter <= _reset_counter + ResetCounterInc;
    end
  end

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile(ImemInitFile)
  ) _imem (
    .clk(clk_12mhz),
    .rst(_rst),
    .ibus(_ibus)
  );

  board_bus _board_bus (
    .clk(clk_12mhz),
    .rst(_rst),
    .led(_led),
    .dip_switch(_dip_switch),
    .push_button(_push_button),
    .uart_tx(uart_tx),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .gpio_in(_gpio_in),
    .gpio_out(_gpio_out),
    .gpio_oe(_gpio_oe),
    .i2c_sda_in(_i2c_sda_in),
    .i2c_sda_drive_low(_i2c_sda_drive_low),
    .i2c_scl_in(_i2c_scl_in),
    .i2c_scl_drive_low(_i2c_scl_drive_low),
    .dbus(_dbus)
  );

  core _core (
    .clk(clk_12mhz),
    .rst(_rst),
    .pc(_pc),
    .halted(_halted),
    .dbus(_dbus),
    .ibus(_ibus)
  );

endmodule
