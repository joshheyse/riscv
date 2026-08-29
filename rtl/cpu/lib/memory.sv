`timescale 1ns / 1ps

module memory
  import riscv_pkg::*;
#(
  parameter int unsigned DepthWords = 512,
  parameter              InitFile   = ""
) (
  input logic        clk,
  input logic        rst,
        mem_if.slave mem
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  localparam int unsigned IndexBits = index_width(DepthWords);

  mem_data_t _memory[0:DepthWords-1];
  initial begin
    if (InitFile != "") begin
      $readmemh(InitFile, _memory);
    end
  end

  logic [IndexBits-1:0] _word_index;
  assign _word_index = mem.req.addr[IndexBits+1:2];

  always_ff @(posedge clk) begin
    if (rst) begin
      mem.rsp <= '0;
    end else begin
      mem.rsp.valid <= mem.req.valid;
      if (mem.req.valid) begin
        mem.rsp.read_data <= _memory[_word_index];
      end
      if (mem.req.valid && mem.req.write_en) begin
        if (mem.req.write_mask[0]) _memory[_word_index][7:0] <= mem.req.write_data[7:0];
        if (mem.req.write_mask[1]) _memory[_word_index][15:8] <= mem.req.write_data[15:8];
        if (mem.req.write_mask[2]) _memory[_word_index][23:16] <= mem.req.write_data[23:16];
        if (mem.req.write_mask[3]) _memory[_word_index][31:24] <= mem.req.write_data[31:24];
      end
    end
  end

endmodule
