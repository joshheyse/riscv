`timescale 1ns / 1ps

// Main decoder: a pure function of instr[6:0], the opcode.
//
// A direct transcription of the Wally main-decoder table, restricted to RV32I
// -- the W64 column and the RW/IW-type rows drop out, since RV32I has no *W
// instructions.
//
//   category op      branch jump alu_src imm_src alu_result_src result_src alu_op reg_write_en mem_write_en
//   R-type   0110011 0      0    RS1_RS2 x       ALU            ALU        1      1         0
//   I-ALU    0010011 0      0    RS1_IMM IMM_I   ALU            ALU        1      1         0
//   load     0000011 0      0    RS1_IMM IMM_I   x              MEM        0      1         0
//   store    0100011 0      0    RS1_IMM IMM_S   x              x          0      0         1
//   branch   1100011 1      0    PC_IMM  IMM_B   x              x          0      0         0
//   jal      1101111 0      1    PC_IMM  IMM_J   PC_PLUS4       ALU        0      1         0
//   jalr     1100111 0      1    RS1_IMM IMM_I   PC_PLUS4       ALU        0      1         0
//   lui      0110111 0      0    x       IMM_U   IMM            ALU        x      1         0
//   auipc    0010111 0      0    PC_IMM  IMM_U   ALU            ALU        0      1         0
//
// Each case arm states only what differs from the defaults, so a row reads as
// "what makes this instruction special". Signals the table marks x are left at
// their defaults; for those opcodes the value is never selected downstream.

module main_decoder
  import riscv_pkg::*;
(
  input  instr_u          instr,
  output logic            reg_write_en,
  output logic            mem_write_en,
  output imm_src_t        imm_src,
  output alu_src_t        alu_src,
  output alu_result_src_t alu_result_src,
  output result_src_t     result_src,
  output logic            branch,
  output logic            jump,
  output logic            alu_op,
  output mem_size_t       mem_size,
  output logic            mem_unsigned,
  output logic            clear_pc_lsb,
  output logic            illegal_main
);

  always_comb begin
    // Defaults fail safe: an opcode this decoder does not recognise commits
    // nothing -- no register write, no memory write, no change of control flow.
    reg_write_en   = 1'b0;
    imm_src        = IMM_I;
    mem_write_en   = 1'b0;
    alu_src        = ALU_SRC_RS1_RS2;
    alu_result_src = ALU_RES_ALU;
    result_src     = RESULT_ALU;
    branch         = 1'b0;
    jump           = 1'b0;
    alu_op         = 1'b0;
    mem_size       = MEM_SIZE_WORD;
    mem_unsigned   = 1'b0;
    clear_pc_lsb   = 1'b0;
    illegal_main   = 1'b0;

    case (instr.r.opcode)
      OP_R: begin
        reg_write_en = 1'b1;
        alu_op    = 1'b1;  // operation comes from funct3/funct7
      end

      OP_I_ALU: begin
        reg_write_en = 1'b1;
        imm_src   = IMM_I;
        alu_src   = ALU_SRC_RS1_IMM;
        alu_op    = 1'b1;
      end

      OP_LOAD: begin
        reg_write_en  = 1'b1;
        imm_src    = IMM_I;
        alu_src    = ALU_SRC_RS1_IMM;  // address = rs1 + imm
        result_src = RESULT_MEM;   // rd gets the loaded value, not the address
      end

      OP_STORE: begin
        mem_write_en = 1'b1;
        imm_src = IMM_S;
        alu_src = ALU_SRC_RS1_IMM;  // address = rs1 + imm; rs2 is the store data
      end

      OP_BRANCH: begin
        branch  = 1'b1;
        imm_src = IMM_B;
        // The ALU computes the target; a separate comparator decides whether
        // the branch is taken.
        alu_src = ALU_SRC_PC_IMM;
      end

      OP_JAL: begin
        reg_write_en   = 1'b1;
        jump           = 1'b1;
        imm_src        = IMM_J;
        alu_src        = ALU_SRC_PC_IMM;  // target = pc + imm
        alu_result_src = ALU_RES_PC_PLUS4;  // but rd gets the return address
      end

      OP_JALR: begin
        reg_write_en   = 1'b1;
        jump           = 1'b1;
        imm_src        = IMM_I;  // I-type, not J-type
        alu_src        = ALU_SRC_RS1_IMM;  // target = rs1 + imm
        alu_result_src = ALU_RES_PC_PLUS4;
        clear_pc_lsb   = 1'b1;
      end

      OP_LUI: begin
        reg_write_en   = 1'b1;
        imm_src        = IMM_U;
        alu_result_src = ALU_RES_IMM;  // the ALU is not used at all
      end

      OP_AUIPC: begin
        reg_write_en   = 1'b1;
        imm_src        = IMM_U;
        alu_src        = ALU_SRC_PC_IMM;  // pc + imm, computed by the ALU
        alu_result_src = ALU_RES_ALU;
      end

      // ecall/ebreak are not implemented; they fall through to the safe
      // defaults, same as an illegal opcode.
      OP_SYSTEM: begin
        illegal_main = 1'b1;
      end

      OP_FENCE: begin
        illegal_main = 1'b0;
      end

      default: begin
        illegal_main = 1'b1;
      end
    endcase

    if ((instr.r.opcode == OP_LOAD) || (instr.r.opcode == OP_STORE)) begin
      // Invalid store funct3 values are not trapped yet; illegal-instruction handling
      // will tighten this later.
      unique case (instr.r.funct3.mem)
        MEM_BYTE: begin
          mem_size = MEM_SIZE_BYTE;
          mem_unsigned = 1'b0;
        end
        MEM_HALF: begin
          mem_size = MEM_SIZE_HALF;
          mem_unsigned = 1'b0;
        end
        MEM_WORD: begin
          mem_size = MEM_SIZE_WORD;
          mem_unsigned = 1'b0;
        end
        MEM_BYTEU: begin
          mem_size     = MEM_SIZE_BYTE;
          mem_unsigned = instr.r.opcode == OP_LOAD ? 1'b1 : 1'b0;
        end
        MEM_HALFU: begin
          mem_size     = MEM_SIZE_HALF;
          mem_unsigned = instr.r.opcode == OP_LOAD ? 1'b1 : 1'b0;
        end
      endcase
    end
  end

endmodule
