`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module top #(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = ""
) (
  input  logic       clk_12mhz,
  input  logic       rst_n,
  output logic [7:0] led_n
);

  logic rst;
  riscv_pkg::pc_t pc;
  riscv_pkg::instr_u instr;
  logic mem_write;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t lsu_read_data;
  logic [7:0] led;
  logic mmio_selected;

  assign rst = ~rst_n;
  assign led_n = ~led;

  assign mem_read_data = mmio_selected ? led_read_data : lsu_read_data;

  imem #(
    .DepthWords(ImemDepthWords),
    .InitFile  (ImemInitFile)
  ) imem_i (
    .addr (pc),
    .instr(instr.raw)
  );

  core core_i (
    .clk(clk_12mhz),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data)
  );

  led_mmio lm (
    .clk(clk_12mhz),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(mmio_selected),
    .read_data(led_read_data),
    .led(led)
  );

  lsu #(
    .DepthWords(DmemDepthWords),
    .InitFile  (DmemInitFile)
  ) lsu_i (
    .clk(clk_12mhz),
    .mem_write(mem_write & !mmio_selected),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(lsu_read_data)
  );

endmodule
