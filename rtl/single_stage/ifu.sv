`timescale 1ns / 1ps

module ifu
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,
  input pc_src_t pc_src,
  input pc_t ieu_addr,
  output pc_t pc
);

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
    end else begin
      pc <= pc_src == PC_SRC_INC ? pc + pc_t'(4) : ieu_addr;
    end
  end

endmodule
