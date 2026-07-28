`timescale 1ns / 1ps

// ALU decoder.
//
// The main decoder first decides whether an instruction needs a real ALU
// operation (`alu_op=1`) or just plain addition for an address/target
// (`alu_op=0`). When `alu_op=1`, RV32I OP/OP-IMM funct3 maps directly to
// `riscv_pkg::alu_select_t`; funct7[5] supplies subtraction/arithmetic-shift selection.
//
//   instruction class       alu_select          sub_arith
//   -----------------       ------------------  ----------------------------
//   load/store/branch/jump  riscv_pkg::ALU_ADDSUB          0
//   add/addi                riscv_pkg::ALU_ADDSUB          0
//   sub                     riscv_pkg::ALU_ADDSUB          1
//   srl/srli                riscv_pkg::ALU_SRL_SRA         0
//   sra/srai                riscv_pkg::ALU_SRL_SRA         1
//   other OP/OP-IMM         instr.r.funct3.alu  0
//
module alu_decoder (
  input logic alu_op,
  input riscv_pkg::instr_u instr,
  output riscv_pkg::alu_select_t alu_select,
  output logic sub_arith,
  output logic illegal_alu
);

  assign alu_select = alu_op ? instr.r.funct3.alu : riscv_pkg::ALU_ADDSUB;

  logic funct7_zero;
  logic funct7_alt;

  assign funct7_zero = instr.r.funct7 == 7'b0000000;
  assign funct7_alt  = instr.r.funct7 == 7'b0100000;

  always_comb begin
    sub_arith   = 1'b0;
    illegal_alu = 1'b0;
    if (alu_op) begin
      unique case (instr.r.opcode)
        riscv_pkg::OP_R: begin
          unique case (instr.r.funct3.alu)
            riscv_pkg::ALU_ADDSUB, riscv_pkg::ALU_SRL_SRA: begin
              illegal_alu = !(funct7_zero || funct7_alt);
              sub_arith   = instr.r.funct7[5];
            end
            default: begin
              illegal_alu = !funct7_zero;
            end
          endcase
        end

        riscv_pkg::OP_I_ALU: begin
          unique case (instr.r.funct3.alu)
            riscv_pkg::ALU_SLL: begin
              illegal_alu = !funct7_zero;
            end
            riscv_pkg::ALU_SRL_SRA: begin
              illegal_alu = !(funct7_zero || funct7_alt);
              sub_arith   = instr.r.funct7[5];
            end
            default: begin
            end
          endcase
        end

        default: begin
          illegal_alu = 1'b1;
        end
      endcase
    end
  end

endmodule
