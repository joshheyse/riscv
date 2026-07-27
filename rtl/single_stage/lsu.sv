`timescale 1ns / 1ps

module lsu
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter string InitFile = ""
) (
  input  logic  clk,
  input  logic  mem_write,
  input  word_t addr,
  input  word_t write_data,
  output word_t read_data
);

  logic [31:0] memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, memory);
    end
  end

  localparam int unsigned IndexBits = $clog2(DepthWords);
  logic [IndexBits-1:0] word_index;

  logic unused_addr_bits;
  assign unused_addr_bits = |{addr[31:IndexBits+2], addr[1:0]};

  assign word_index = addr[IndexBits+1:2];
  assign read_data = memory[word_index];

  always_ff @(posedge clk) begin
    if (mem_write) begin
      memory[word_index] <= write_data;
    end else begin
    end
  end


endmodule
