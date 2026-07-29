`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module top #(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned PowerOnResetCycles = 16,
  parameter int unsigned NumGpio = memmap_pkg::NumGpio
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
  output logic               spi_cs_n
);

  localparam int unsigned ResetCounterBits = $clog2(PowerOnResetCycles + 1);
  localparam logic [ResetCounterBits-1:0] ResetCounterMax = ResetCounterBits'(PowerOnResetCycles);
  localparam logic [ResetCounterBits-1:0] ResetCounterInc = ResetCounterBits'(1);
  /* verilator lint_off PROCASSINIT */
  logic [ResetCounterBits-1:0] reset_counter = '0;
  /* verilator lint_on PROCASSINIT */

  logic rst;
  logic power_on_rst;
  riscv_pkg::pc_t pc;
  riscv_pkg::instr_u instr;
  logic [7:0] led;
  logic [7:0] dip_switch;
  logic [NumGpio-1:0] gpio_in;
  logic [NumGpio-1:0] gpio_out;
  logic [NumGpio-1:0] gpio_oe;
  logic push_button;
  logic halted;
  logic mem_write;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::mem_size_t mem_size;
  logic mem_unsigned;

  initial begin
    assert (PowerOnResetCycles > 0);
  end

  assign power_on_rst = (reset_counter != ResetCounterMax);
  assign rst = ~rst_n | power_on_rst;
  assign led_n = halted ? 8'h00 : ~led;
  assign dip_switch = ~dip_switch_n;
  assign push_button = ~push_button_n;
  assign gpio_in = gpio;

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
    .addr (pc),
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
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

  core core_i (
    .clk(clk_12mhz),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .halted(halted),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

endmodule
