`timescale 1ns / 1ps

module lru_4_way
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

  logic [2:0] _plru_tree[CacheNumSets];

  always_comb begin
    victim_way = {
      _plru_tree[victim_set][1],
      _plru_tree[victim_set][1] ? _plru_tree[victim_set][0] : _plru_tree[victim_set][2]
    };
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _plru_tree <= '{default: '0};
    end else begin
      if (touch_valid) begin
        case (touch_way)
          (2'b00): begin
            _plru_tree[touch_set][2:1] <= 2'b11;
          end
          (2'b01): begin
            _plru_tree[touch_set][2:1] <= 2'b01;
          end
          (2'b10): begin
            _plru_tree[touch_set][1:0] <= 2'b01;
          end
          (2'b11): begin
            _plru_tree[touch_set][1:0] <= 2'b00;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule
