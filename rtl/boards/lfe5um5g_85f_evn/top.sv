`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board top.
//
// Board-specific shell around the portable single-stage core: clock/reset pins,
// active-low LEDs, instruction memory, data memory, and LED MMIO live here.
module top #(
  parameter int unsigned ImemDepthWords = 512,
  parameter ImemInitFile = "",
  parameter int unsigned DmemDepthWords = 512,
  parameter DmemInitFile = "",
  parameter int unsigned PowerOnResetCycles = 16
) (
  input  logic       clk_12mhz,
  input  logic       rst_n,
  output logic [7:0] led_n,
  output logic       uart_tx
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
  logic mem_write;
  riscv_pkg::word_t mem_addr;
  riscv_pkg::word_t mem_write_data;
  riscv_pkg::word_t mem_read_data;
  riscv_pkg::word_t led_read_data;
  riscv_pkg::word_t uart_read_data;
  riscv_pkg::word_t lsu_read_data;
  riscv_pkg::mem_size_t mem_size;
  logic mem_unsigned;
  logic [7:0] led;
  logic led_selected;
  logic uart_selected;
  logic mmio_selected;
  logic halted;

  initial begin
    assert (PowerOnResetCycles > 0);
  end

  assign power_on_rst = (reset_counter != ResetCounterMax);
  assign rst = ~rst_n | power_on_rst;
  assign led_n = halted ? 8'h00 : ~led;

  assign mmio_selected = led_selected | uart_selected;
  assign mem_read_data = led_selected ? led_read_data : (uart_selected ? uart_read_data : lsu_read_data);

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

  core core_i (
    .clk(clk_12mhz),
    .rst(rst),
    .instr(instr),
    .pc(pc),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .halted(halted)
  );

  led_mmio lm (
    .clk(clk_12mhz),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(led_selected),
    .read_data(led_read_data),
    .led(led)
  );

  uart_mmio um (
    .clk(clk_12mhz),
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
    .clk(clk_12mhz),
    .mem_write(mem_write & !mmio_selected),
    .addr(mem_addr),
    .write_data(mem_write_data),
    .read_data(lsu_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
  );

endmodule
