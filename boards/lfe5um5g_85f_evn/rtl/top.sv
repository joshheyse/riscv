`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable pipelined core: clock/reset pins,
// active-low LEDs, unified memory, and MMIO live here.
module top
  import riscv_pkg::*;
#(
  parameter int unsigned MemDepthWords      = 1024,
  parameter              MemInitFile        = "",
  parameter int unsigned PowerOnResetCycles = 16,
  parameter int unsigned NumGpio            = board_constants_pkg::NumGpio
) (
  input  logic               clk_12mhz,
  input  logic               rst_n,
  output logic [        7:0] led_n,
  input  logic [        7:0] dip_switch_n,
  input  logic               push_button_n,
  inout  logic [NumGpio-1:0] gpio,
  input  logic               uart_rx,
  output logic               uart_tx,
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
  /* verilator lint_off UNUSEDSIGNAL */
  pc_t                         _pc;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem ();
  irq_if _irq ();

  logic [        7:0] _led;
  logic [        7:0] _dip_switch;
  logic               _push_button;

  logic [NumGpio-1:0] _gpio_in;
  logic [NumGpio-1:0] _gpio_out;
  logic [NumGpio-1:0] _gpio_oe;
  uart_if _uart ();
  spi_if  _spi ();
  i2c_if  _i2c ();

  initial begin
    assert (PowerOnResetCycles > 0);
  end

  assign _power_on_rst = (_reset_counter != ResetCounterMax);
  assign _rst = ~rst_n | _power_on_rst;

  assign led_n = _halted ? 8'h00 : ~_led;
  assign _dip_switch = ~dip_switch_n;
  assign _push_button = ~push_button_n;
  assign _gpio_in = gpio;

  assign _uart.rx = uart_rx;
  assign uart_tx = _uart.tx;

  assign _spi.miso = spi_miso;
  assign spi_sck = _spi.sck;
  assign spi_mosi = _spi.mosi;
  assign spi_cs_n = _spi.cs_n;

  assign _i2c.sda_in = i2c_sda;
  assign _i2c.scl_in = i2c_scl;
  assign i2c_sda = _i2c.sda_drive_low ? 1'b0 : 1'bz;
  assign i2c_scl = _i2c.scl_drive_low ? 1'b0 : 1'bz;

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

  board_bus #(
    .MemDepthWords(MemDepthWords),
    .MemInitFile(MemInitFile)
  ) _board_bus (
    .clk(clk_12mhz),
    .rst(_rst),
    .led(_led),
    .dip_switch(_dip_switch),
    .push_button(_push_button),
    .uart(_uart),
    .spi(_spi),
    .i2c(_i2c),
    .gpio_in(_gpio_in),
    .gpio_out(_gpio_out),
    .gpio_oe(_gpio_oe),
    .mem(_mem),
    .irq(_irq)
  );

  core _core (
    .clk(clk_12mhz),
    .rst(_rst),
    .pc(_pc),
    .halted(_halted),
    .mem(_mem),
    .irq(_irq)
  );

endmodule
