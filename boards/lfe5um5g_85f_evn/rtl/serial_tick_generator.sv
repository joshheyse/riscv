`timescale 1ns / 1ps

module serial_tick_generator #(
  parameter int unsigned ClocksPerTick = 60
) (
  input  logic clk,
  input  logic rst,
  input  logic enable,
  input  logic clear,
  output logic tick
);

  localparam int unsigned CounterBits = (ClocksPerTick <= 1) ? 1 : $clog2(ClocksPerTick);
  localparam logic [CounterBits-1:0] TerminalCount = CounterBits'(ClocksPerTick - 1);
  logic [CounterBits-1:0] counter;

  always_ff @(posedge clk) begin
    if (rst) begin
      counter <= 0;
      tick <= 1'b0;
    end else if (clear || !enable) begin
      counter <= 0;
      tick <= 1'b0;
    end else if (counter == TerminalCount) begin
      counter <= 0;
      tick <= 1'b1;
    end else begin
      counter <= counter + 1;
      tick <= 1'b0;
    end
  end

endmodule
