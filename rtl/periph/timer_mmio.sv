`timescale 1ns / 1ps

module timer_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t TimerLoAddr = '0,
  parameter mem_addr_t TimerHiAddr = '0
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            mem_valid,
  input  logic            mem_write_en,
  input  mem_addr_t       mem_addr,
  input  mem_data_t       mem_write_data,
  input  mem_write_mask_t mem_write_mask,
  output logic            selected,
  output logic            mem_ready,
  output mem_data_t       mem_read_data
);

  dword_t _counter;
  assign selected = mem_addr == TimerLoAddr || mem_addr == TimerHiAddr;
  assign mem_ready = mem_valid && selected;
  assign mem_read_data = !selected ? '0 : (mem_addr == TimerLoAddr) ? _counter[31:0] : _counter[63:32];

  always_ff @(posedge clk) begin
    if (rst) begin
      _counter <= '0;
    end else begin
      _counter <= _counter + 1;
    end
  end

  logic _unused_write_bus;
  assign _unused_write_bus = mem_write_en | (|mem_write_data) | (|mem_write_mask);

endmodule
