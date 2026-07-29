`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module board_bus #(
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = ""
) (
  input  logic                       clk,
  input  logic                       rst,
  output logic                 [7:0] led,
  output logic                       uart_tx,
  input  logic                       mem_write,
  input  riscv_pkg::word_t           mem_addr,
  input  riscv_pkg::word_t           mem_write_data,
  output riscv_pkg::word_t           mem_read_data,
  input  riscv_pkg::mem_size_t       mem_size,
  input  logic                       mem_unsigned
);

  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t lsu_read_data;
  riscv_pkg::word_t timer_read_data;
  logic dmem_selected;
  logic led_selected;
  logic uart_selected;
  logic timer_selected;
  logic mmio_selected;
  logic dmem_write;
  logic led_write;
  logic uart_write;

  assign dmem_selected = ((mem_addr - memmap_pkg::DmemBase) < memmap_pkg::DmemSize);
  assign mmio_selected = led_selected | uart_selected | timer_selected;
  assign dmem_write    = mem_write & dmem_selected & !mmio_selected;
  assign led_write     = mem_write & led_selected;
  assign uart_write    = mem_write & uart_selected;

  always_comb begin
    mem_read_data = '0;

    if (led_selected) begin
      mem_read_data = led_read_data;
    end else if (uart_selected) begin
      mem_read_data = uart_read_data;
    end else if (timer_selected) begin
      mem_read_data = timer_read_data;
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

  timer_mmio tm (
    .clk(clk),
    .rst(rst),
    .mem_addr(mem_addr),
    .selected(timer_selected),
    .read_data(timer_read_data)
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
