`timescale 1ns / 1ps

module dmem
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter InitFile = ""
) (
  input logic clk,
  input logic rst,
  input logic mem_valid,
  input logic mem_write_en,
  input word_t addr,
  input word_t write_data,
  input logic [3:0] write_mask,
  output logic mem_ready,
  output word_t read_data
);
  word_t _memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _memory);
    end
  end

  localparam int unsigned IndexBits = $clog2(DepthWords);
  logic [IndexBits-1:0] _word_index;
  assign _word_index = addr[IndexBits+1:2];

  always_ff @(posedge clk) begin
    if (rst) begin
      read_data <= '0;
      mem_ready <= 1'b0;
    end else begin
      mem_ready <= mem_valid;
      if (mem_valid) begin
        read_data <= _memory[_word_index];
      end
      if (mem_valid && mem_write_en) begin
        if (write_mask[0]) _memory[_word_index][7:0] <= write_data[7:0];
        if (write_mask[1]) _memory[_word_index][15:8] <= write_data[15:8];
        if (write_mask[2]) _memory[_word_index][23:16] <= write_data[23:16];
        if (write_mask[3]) _memory[_word_index][31:24] <= write_data[31:24];
      end
    end
  end

  logic _unused_addr_bits;
  assign _unused_addr_bits = |{addr[31:IndexBits+2], addr[1:0]};

endmodule
