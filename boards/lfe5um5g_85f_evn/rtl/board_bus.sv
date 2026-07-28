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
  output logic       uart_tx,
  input  logic       mem_write,
  input  riscv_pkg::word_t mem_addr,
  input  riscv_pkg::word_t mem_write_data,
  output riscv_pkg::word_t mem_read_data,
  input  riscv_pkg::mem_size_t mem_size,
  input  logic       mem_unsigned
);

  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t lsu_read_data;
  logic dmem_selected;
  logic led_selected;
  logic uart_selected;
  logic mmio_selected;

  assign dmem_selected = ((mem_addr - memmap_pkg::DmemBase) < memmap_pkg::DmemSize);
  assign mmio_selected = led_selected | uart_selected;
  assign mem_read_data = dmem_selected ? lsu_read_data : (led_selected ? led_read_data : (uart_selected ? uart_read_data : '0));

  led_mmio lm (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(led_selected),
    .read_data(led_read_data),
    .led(led)
  );

  uart_mmio um (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(uart_selected),
    .read_data(uart_read_data),
    .tx(uart_tx)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) lsu_i (
    .clk(clk),
    .mem_write(mem_write & dmem_selected & !mmio_selected),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(lsu_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

endmodule
