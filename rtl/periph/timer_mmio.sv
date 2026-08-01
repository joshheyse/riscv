`timescale 1ns / 1ps

module timer_mmio
  import riscv_pkg::*;
#(
  parameter word_t TimerLoAddr = '0,
  parameter word_t TimerHiAddr = '0
) (
  input  logic  clk,
  input  logic  rst,
  input  word_t mem_addr,
  output logic  selected,
  output word_t read_data
);

  dword_t counter;
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
