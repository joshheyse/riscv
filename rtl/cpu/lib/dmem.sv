`timescale 1ns / 1ps

module dmem
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter              InitFile   = ""
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            mem_valid,
  input  logic            mem_write_en,
  input  mem_addr_t       mem_addr,
  input  mem_data_t       mem_write_data,
  input  logic      [3:0] mem_write_mask,
  output logic            mem_ready,
  output mem_data_t       mem_read_data
);

  localparam int unsigned IndexBits = $clog2(DepthWords);


  mem_data_t _memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _memory);
    end
  end

  logic [IndexBits-1:0] _word_index;
  assign _word_index = mem_addr[IndexBits+1:2];

  always_ff @(posedge clk) begin
    if (rst) begin
      mem_read_data <= '0;
      mem_ready <= 1'b0;
    end else begin
      mem_ready <= mem_valid;
      if (mem_valid) begin
        mem_read_data <= _memory[_word_index];
      end
      if (mem_valid && mem_write_en) begin
        if (mem_write_mask[0]) _memory[_word_index][7:0] <= mem_write_data[7:0];
        if (mem_write_mask[1]) _memory[_word_index][15:8] <= mem_write_data[15:8];
        if (mem_write_mask[2]) _memory[_word_index][23:16] <= mem_write_data[23:16];
        if (mem_write_mask[3]) _memory[_word_index][31:24] <= mem_write_data[31:24];
      end
    end
  end

  logic _unused_addr_bits;
  assign _unused_addr_bits = |{mem_addr[31:IndexBits+2], mem_addr[1:0]};

endmodule
