`timescale 1ns / 1ps

module reg_file
  import riscv_pkg::*;
(
  input logic clk,
  input regaddr_t rd_addr1,
  input regaddr_t rd_addr2,
  input regaddr_t wr_addr,
  input word_t wr_data,
  input logic wr_en,
  output word_t rd_data1,
  output word_t rd_data2
);

  logic [31:0] regs[31:0];

  assign rd_data1 = rd_addr1 == '0 ? '0 : regs[rd_addr1];
  assign rd_data2 = rd_addr2 == '0 ? '0 : regs[rd_addr2];

  always_ff @(posedge clk) begin
    if (wr_en) begin
      regs[wr_addr] <= wr_data;
    end
  end

endmodule
