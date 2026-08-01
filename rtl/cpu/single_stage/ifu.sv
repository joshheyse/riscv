`timescale 1ns / 1ps

// Instruction fetch unit: the PC register and next-PC mux.
//
// The IFU does not contain instruction memory. It only chooses the next PC:
//
//   rst     pc_src          next pc
//   ---     -------------   ----------------
//   1       x               0
//   0       PC_SRC_INC      pc + 4
//   0       PC_SRC_IEU_ADR  ieu_addr
//
// `ieu_addr` is computed by the datapath ALU for branches, JAL, and JALR.
//
module ifu
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,
  input pc_src_t pc_src,
  input logic pc_en,
  input pc_t ieu_addr,
  output pc_t pc,
  output pc_t imem_addr,
  output logic instr_valid
);

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
      imem_addr <= '0;
      instr_valid <= '0;
    end else begin
      if (pc_en) begin
        pc <= imem_addr;
        imem_addr <= pc_src == PC_SRC_INC ? imem_addr + pc_t'(4) : ieu_addr;
        instr_valid <= pc_src == PC_SRC_INC;
      end
    end
  end

endmodule
