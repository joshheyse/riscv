`timescale 1ns / 1ps

module timer_mmio #(
  parameter riscv_pkg::word_t TimerLoAddr = memmap_pkg::TimerLoAddr,
  parameter riscv_pkg::word_t TimerHiAddr = memmap_pkg::TimerHiAddr
) (
  input logic clk,
  input logic rst,
  input riscv_pkg::word_t mem_addr,
  output logic selected,
  output riscv_pkg::word_t read_data
);

  riscv_pkg::dword_t counter;
  assign selected  = mem_addr == TimerLoAddr || mem_addr == TimerHiAddr;
  assign read_data = !selected ? '0 : (mem_addr == TimerLoAddr) ? counter[31:0] : counter[63:32];

  always_ff @(posedge clk) begin
    if (rst) begin
      counter <= '0;
    end else begin
      counter <= counter + 1;
    end
  end

endmodule
