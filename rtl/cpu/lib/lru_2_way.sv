`timescale 1ns / 1ps

module lru_2_way
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  input logic       touch_valid,
  input set_index_t touch_set,
  input way_index_t touch_way,

  input  set_index_t victim_set,
  output way_index_t victim_way
);

  logic [CacheNumSets-1:0] _lru_victim;

  always_comb begin
    victim_way = way_index_t'(_lru_victim[victim_set]);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _lru_victim <= '0;
    end else begin
      if (touch_valid) begin
        _lru_victim[touch_set] <= ~touch_way;
      end
    end
  end

endmodule
