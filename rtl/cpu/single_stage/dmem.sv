`timescale 1ns / 1ps

module dmem #(
  parameter int unsigned DepthWords = 512,
  parameter InitFile = ""
) (
  input logic clk,
  input logic mem_write,
  input riscv_pkg::word_t addr,
  input riscv_pkg::word_t write_data,
  output riscv_pkg::word_t read_data
);
  riscv_pkg::word_t memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, memory);
    end
  end

  localparam int unsigned IndexBits = $clog2(DepthWords);
  logic [IndexBits-1:0] word_index;

  assign word_index = addr[IndexBits+1:2];
  assign read_data  = memory[word_index];

  always_ff @(posedge clk) begin
    if (mem_write) begin
      memory[word_index] <= write_data;
    end
  end

  logic unused_addr_bits;
  assign unused_addr_bits = |{{addr[31:IndexBits+2], addr[1:0]}};

endmodule
