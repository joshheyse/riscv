`timescale 1ns / 1ps

// ALU decoder.
//
// The main decoder first decides whether an instruction needs a real ALU
// operation (`alu_decode_en=1`) or just plain addition for an address/target
// (`alu_decode_en=0`). When `alu_decode_en=1`, RV32I OP/OP-IMM funct3 maps directly to
// `alu_op_t`; funct7[5] supplies subtraction/arithmetic-shift selection.
//
//   instruction class       alu_op          sub_arith
//   -----------------       ------------------  ----------------------------
//   load/store/branch/jump  ALU_ADDSUB          0
//   add/addi                ALU_ADDSUB          0
//   sub                     ALU_ADDSUB          1
//   srl/srli                ALU_SRL_SRA         0
//   sra/srai                ALU_SRL_SRA         1
//   other OP/OP-IMM         instr.r.funct3.alu  0
//
module alu_decoder
  import riscv_pkg::*;
(
  input  logic    alu_decode_en,
  input  instr_u  instr,
  output alu_op_t alu_op,
  output logic    sub_arith,
  output logic    alu_op_illegal
);

  assign alu_op = alu_decode_en ? instr.r.funct3.alu : ALU_ADDSUB;

  logic _funct7_zero;
  logic _funct7_alt;

  assign _funct7_zero = instr.r.funct7 == 7'b0000000;
  assign _funct7_alt  = instr.r.funct7 == 7'b0100000;

  always_comb begin
    sub_arith = 1'b0;
    alu_op_illegal = 1'b0;
    if (alu_decode_en) begin
      // slang lint_off case-enum-explicit
      case (instr.r.opcode)
        OP_R: begin
          case (instr.r.funct3.alu)
            ALU_ADDSUB, ALU_SRL_SRA: begin
              alu_op_illegal = !(_funct7_zero || _funct7_alt);
              sub_arith = instr.r.funct7[5];
            end
            default: begin
              alu_op_illegal = !_funct7_zero;
            end
          endcase
        end

        OP_I_ALU: begin
          case (instr.r.funct3.alu)
            ALU_SLL: begin
              alu_op_illegal = !_funct7_zero;
            end
            ALU_SRL_SRA: begin
              alu_op_illegal = !(_funct7_zero || _funct7_alt);
              sub_arith = instr.r.funct7[5];
            end
            default: begin
            end
          endcase
        end

        default: begin
          alu_op_illegal = 1'b1;
        end
      endcase
      // slang lint_on case-enum-explicit
    end
  end

endmodule
