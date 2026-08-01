`timescale 1ns / 1ps

// RV32I integer register file.
//
// Register fields come straight from fixed instruction bit positions:
//
//   instr[19:15]  rs1 -> rd_addr1
//   instr[24:20]  rs2 -> rd_addr2
//   instr[11:7]   rd  -> wr_addr
//
// Reads are combinational and x0 is hard-wired to zero on both read ports.
// Writes occur on the rising clock edge when `wr_en` is asserted.
//
module reg_file
  import riscv_pkg::*;
(
  input  logic     clk,
  input  regaddr_t rd_addr1,
  input  regaddr_t rd_addr2,
  input  regaddr_t wr_addr,
  input  word_t    wr_data,
  input  logic     wr_en,
  output word_t    rd_data1,
  output word_t    rd_data2
);

  logic [31:0] _regs[31:0];

  assign rd_data1 = rd_addr1 == '0 ? '0 : _regs[rd_addr1];
  assign rd_data2 = rd_addr2 == '0 ? '0 : _regs[rd_addr2];

  always_ff @(posedge clk) begin
    if (wr_en) begin
      _regs[wr_addr] <= wr_data;
    end
  end

endmodule
