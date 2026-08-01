`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module top
  import riscv_pkg::*;
#(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned PowerOnResetCycles = 16,
  parameter int unsigned NumGpio = board_constants_pkg::NumGpio
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
  logic [ResetCounterBits-1:0] reset_counter = '0;
  /* verilator lint_on PROCASSINIT */

  logic rst;
  logic power_on_rst;
  pc_t pc;
  pc_t imem_addr;
  instr_u instr;
  logic halted;

  logic imem_en;
  dbus_if dbus ();

  logic [7:0] led;
  logic [7:0] dip_switch;
  logic push_button;

  logic [NumGpio-1:0] gpio_in;
  logic [NumGpio-1:0] gpio_out;
  logic [NumGpio-1:0] gpio_oe;

  logic i2c_sda_in;
  logic i2c_sda_drive_low;
  logic i2c_scl_in;
  logic i2c_scl_drive_low;

  initial begin
    assert (PowerOnResetCycles > 0);
  end

  assign power_on_rst = (reset_counter != ResetCounterMax);
  assign rst = ~rst_n | power_on_rst;

  assign led_n = halted ? 8'h00 : ~led;
  assign dip_switch = ~dip_switch_n;
  assign push_button = ~push_button_n;
  assign gpio_in = gpio;

  assign i2c_sda_in = i2c_sda;
  assign i2c_scl_in = i2c_scl;

  assign i2c_sda = i2c_sda_drive_low ? 1'b0 : 1'bz;
  assign i2c_scl = i2c_scl_drive_low ? 1'b0 : 1'bz;

  genvar i;
  generate
    for (i = 0; i < NumGpio; i++) begin : gen_gpio_tristate
      assign gpio[i] = gpio_oe[i] ? gpio_out[i] : 1'bz;
    end
  endgenerate

  always_ff @(posedge clk_12mhz) begin
    if (!rst_n) begin
      reset_counter <= '0;
    end else if (power_on_rst) begin
      reset_counter <= reset_counter + ResetCounterInc;
    end
  end

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) imem_i (
    .clk(clk_12mhz),
    .rst(rst),
    .en(imem_en),
    .addr(imem_addr),
    .instr(instr.raw)
  );

  board_bus bus (
    .clk(clk_12mhz),
    .rst(rst),
    .led(led),
    .dip_switch(dip_switch),
    .push_button(push_button),
    .uart_tx(uart_tx),
    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe),
    .i2c_sda_in(i2c_sda_in),
    .i2c_sda_drive_low(i2c_sda_drive_low),
    .i2c_scl_in(i2c_scl_in),
    .i2c_scl_drive_low(i2c_scl_drive_low),
    .dbus(dbus)
  );

  core core_i (
    .clk(clk_12mhz),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .imem_addr(imem_addr),
    .halted(halted),
    .dbus(dbus),
    .imem_en(imem_en)
  );

endmodule
