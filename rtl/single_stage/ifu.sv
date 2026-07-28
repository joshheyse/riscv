`timescale 1ns / 1ps

// Instruction fetch unit: the PC register and next-PC mux.
//
// The IFU does not contain instruction memory. It only chooses the next PC:
//
//   rst     pc_src          next pc
//   ---     -------------   ----------------
//   1       x               0
//   0       riscv_pkg::PC_SRC_INC      pc + 4
//   0       riscv_pkg::PC_SRC_IEU_ADR  ieu_addr
//
// `ieu_addr` is computed by the datapath ALU for branches, JAL, and JALR.
//
module ifu (
  input logic clk,
  input logic rst,
  input riscv_pkg::pc_src_t pc_src,
  input riscv_pkg::pc_t ieu_addr,
  output riscv_pkg::pc_t pc
);

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
    end else begin
      pc <= pc_src == riscv_pkg::PC_SRC_INC ? pc + riscv_pkg::pc_t'(4) : ieu_addr;
    end
  end

endmodule
