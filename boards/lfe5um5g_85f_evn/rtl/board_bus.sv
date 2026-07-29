`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module board_bus #(
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = ""
) (
  input  logic       clk,
  input  logic       rst,
  output logic [7:0] led,
  input  logic [7:0] dip_switch,
  input  logic       push_button,
  output logic       uart_tx,

  output logic spi_sck,
  output logic spi_mosi,
  input  logic spi_miso,
  output logic spi_cs_n,

  input  logic                 mem_write,
  input  riscv_pkg::word_t     mem_addr,
  input  riscv_pkg::word_t     mem_write_data,
  output riscv_pkg::word_t     mem_read_data,
  input  riscv_pkg::mem_size_t mem_size,
  input  logic                 mem_unsigned
);

  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t lsu_read_data;
  riscv_pkg::word_t timer_read_data;
  riscv_pkg::word_t dip_switch_read_data;
  riscv_pkg::word_t push_button_read_data;
  riscv_pkg::word_t spi_read_data;
  logic dmem_selected;
  logic led_selected;
  logic uart_selected;
  logic timer_selected;
  logic dip_switch_selected;
  logic push_button_selected;
  logic spi_selected;
  logic mmio_selected;
  logic dmem_write;
  logic led_write;
  logic uart_write;
  logic spi_write;

  assign dmem_selected = ((mem_addr - memmap_pkg::DmemBase) < memmap_pkg::DmemSize);
  assign mmio_selected = led_selected | uart_selected | timer_selected | dip_switch_selected | push_button_selected | spi_selected;
  assign dmem_write = mem_write & dmem_selected & !mmio_selected;
  assign led_write = mem_write & led_selected;
  assign uart_write = mem_write & uart_selected;
  assign spi_write = mem_write & spi_selected;

  always_comb begin
    mem_read_data = '0;

    if (led_selected) begin
      mem_read_data = led_read_data;
    end else if (uart_selected) begin
      mem_read_data = uart_read_data;
    end else if (timer_selected) begin
      mem_read_data = timer_read_data;
    end else if (dip_switch_selected) begin
      mem_read_data = dip_switch_read_data;
    end else if (push_button_selected) begin
      mem_read_data = push_button_read_data;
    end else if (spi_selected) begin
      mem_read_data = spi_read_data;
    end else if (dmem_selected) begin
      mem_read_data = lsu_read_data;
    end
  end

  led_mmio lm (
    .clk(clk),
    .rst(rst),
    .mem_write(led_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(led_selected),
    .read_data(led_read_data),
    .led(led)
  );

  dip_switch_mmio dm (
    .mem_addr  (mem_addr),
    .selected  (dip_switch_selected),
    .read_data (dip_switch_read_data),
    .dip_switch(dip_switch)
  );

  push_button_mmio pbm (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(push_button_selected),
    .read_data(push_button_read_data),
    .push_button(push_button)
  );

  timer_mmio tm (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(timer_selected),
    .read_data(timer_read_data)
  );

  uart_mmio #(
    .ClocksPerBit(memmap_pkg::UartClocksPerBit)
  ) um (
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
    .ClocksPerHalfBit(memmap_pkg::SpiClocksPerHalfBit)
  ) sm (
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
