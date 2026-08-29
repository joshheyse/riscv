`timescale 1ns / 1ps

module serial_tick_generator
  import riscv_pkg::*;
#(
  parameter int unsigned ClocksPerTick = 60
) (
  input  logic clk,
  input  logic rst,
  input  logic en,
  input  logic clear,
  output logic tick
);

  localparam int unsigned CounterBits = index_width(ClocksPerTick);
  localparam logic [CounterBits-1:0] TerminalCount = CounterBits'(ClocksPerTick - 1);
  logic [CounterBits-1:0] _counter;

  assign tick = en && !clear && (_counter == TerminalCount);

  always_ff @(posedge clk) begin
    if (rst) begin
      _counter <= 0;
    end else if (clear || !en) begin
      _counter <= 0;
    end else if (_counter == TerminalCount) begin
      _counter <= 0;
    end else begin
      _counter <= _counter + 1;
    end
  end

endmodule
