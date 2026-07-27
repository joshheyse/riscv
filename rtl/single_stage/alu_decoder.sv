`timescale 1ns / 1ps

// ALU decoder.
//
// The main decoder first decides whether an instruction needs a real ALU
// operation (`alu_op=1`) or just plain addition for an address/target
// (`alu_op=0`). When `alu_op=1`, RV32I OP/OP-IMM funct3 maps directly to
// `alu_select_t`; funct7[5] supplies subtraction/arithmetic-shift selection.
//
//   instruction class       alu_select          sub_arith
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
  input logic alu_op,
  input instr_u instr,
  output alu_select_t alu_select,
  output logic sub_arith
);

  assign alu_select = alu_op ? instr.r.funct3.alu : ALU_ADDSUB;

  always_comb begin
    sub_arith = 1'b0;
    if (alu_op) begin
      case (instr.r.funct3.alu)
        ALU_ADDSUB: begin
          // opcode[5] distinguishes R-type from I-type. There is no SUBI, and
          // for an I-type instruction bit 30 is immediate data -- addi with a
          // negative immediate has it set.
          sub_arith = instr.r.funct7[5] & instr.r.opcode[5];
        end
        ALU_SRL_SRA: begin
          // No opcode gate: srai is a legal I-type, because a shift immediate
          // is only 5 bits and the ISA fixes imm[11:5] to 0000000 or 0100000.
          sub_arith = instr.r.funct7[5];
        end
        default: begin
        end
      endcase
    end
  end


endmodule
