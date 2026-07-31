`timescale 1ns / 1ps

// Main decoder: a pure function of instr[6:0], the opcode.
//
// A direct transcription of the Wally main-decoder table, restricted to RV32I
// -- the W64 column and the RW/IW-type rows drop out, since RV32I has no *W
// instructions.
//
//   category op      branch jump alu_src imm_src alu_result_src result_src alu_op reg_write mem_write
//   R-type   0110011 0      0    RS1_RS2 x       ALU            ALU        1      1         0
//   I-ALU    0010011 0      0    RS1_IMM riscv_pkg::IMM_I   ALU            ALU        1      1         0
//   load     0000011 0      0    RS1_IMM riscv_pkg::IMM_I   x              MEM        0      1         0
//   store    0100011 0      0    RS1_IMM riscv_pkg::IMM_S   x              x          0      0         1
//   branch   1100011 1      0    PC_IMM  riscv_pkg::IMM_B   x              x          0      0         0
//   jal      1101111 0      1    PC_IMM  riscv_pkg::IMM_J   PC_PLUS4       ALU        0      1         0
//   jalr     1100111 0      1    RS1_IMM riscv_pkg::IMM_I   PC_PLUS4       ALU        0      1         0
//   lui      0110111 0      0    x       riscv_pkg::IMM_U   IMM            ALU        x      1         0
//   auipc    0010111 0      0    PC_IMM  riscv_pkg::IMM_U   ALU            ALU        0      1         0
//
// Each case arm states only what differs from the defaults, so a row reads as
// "what makes this instruction special". Signals the table marks x are left at
// their defaults; for those opcodes the value is never selected downstream.

module main_decoder (
  input riscv_pkg::instr_u instr,
  output logic reg_write,
  output logic mem_write,
  output riscv_pkg::imm_src_t imm_src,
  output riscv_pkg::alu_src_t alu_src,
  output riscv_pkg::alu_result_src_t alu_result_src,
  output riscv_pkg::result_src_t result_src,
  output logic branch,
  output logic jump,
  output logic alu_op,
  output riscv_pkg::mem_size_t mem_size,
  output logic mem_unsigned,
  output logic clear_pc_lsb,
  output logic illegal_main
);

  always_comb begin
    // Defaults fail safe: an opcode this decoder does not recognise commits
    // nothing -- no register write, no memory write, no change of control flow.
    reg_write      = 1'b0;
    imm_src        = riscv_pkg::IMM_I;
    mem_write      = 1'b0;
    alu_src        = riscv_pkg::ALU_SRC_RS1_RS2;
    alu_result_src = riscv_pkg::ALU_RES_ALU;
    result_src     = riscv_pkg::RESULT_ALU;
    branch         = 1'b0;
    jump           = 1'b0;
    alu_op         = 1'b0;
    mem_size       = riscv_pkg::MEM_SIZE_WORD;
    mem_unsigned   = 1'b0;
    clear_pc_lsb   = 1'b0;
    illegal_main   = 1'b0;

    case (instr.r.opcode)
      riscv_pkg::OP_R: begin
        reg_write = 1'b1;
        alu_op    = 1'b1;  // operation comes from funct3/funct7
      end

      riscv_pkg::OP_I_ALU: begin
        reg_write = 1'b1;
        imm_src   = riscv_pkg::IMM_I;
        alu_src   = riscv_pkg::ALU_SRC_RS1_IMM;
        alu_op    = 1'b1;
      end

      riscv_pkg::OP_LOAD: begin
        reg_write  = 1'b1;
        imm_src    = riscv_pkg::IMM_I;
        alu_src    = riscv_pkg::ALU_SRC_RS1_IMM;  // address = rs1 + imm
        result_src = riscv_pkg::RESULT_MEM;   // rd gets the loaded value, not the address
      end

      riscv_pkg::OP_STORE: begin
        mem_write = 1'b1;
        imm_src   = riscv_pkg::IMM_S;
        alu_src   = riscv_pkg::ALU_SRC_RS1_IMM;  // address = rs1 + imm; rs2 is the store data
      end

      riscv_pkg::OP_BRANCH: begin
        branch  = 1'b1;
        imm_src = riscv_pkg::IMM_B;
        // The ALU computes the target; a separate comparator decides whether
        // the branch is taken.
        alu_src = riscv_pkg::ALU_SRC_PC_IMM;
      end

      riscv_pkg::OP_JAL: begin
        reg_write      = 1'b1;
        jump           = 1'b1;
        imm_src        = riscv_pkg::IMM_J;
        alu_src        = riscv_pkg::ALU_SRC_PC_IMM;  // target = pc + imm
        alu_result_src = riscv_pkg::ALU_RES_PC_PLUS4;  // but rd gets the return address
      end

      riscv_pkg::OP_JALR: begin
        reg_write      = 1'b1;
        jump           = 1'b1;
        imm_src        = riscv_pkg::IMM_I;  // I-type, not J-type
        alu_src        = riscv_pkg::ALU_SRC_RS1_IMM;  // target = rs1 + imm
        alu_result_src = riscv_pkg::ALU_RES_PC_PLUS4;
        clear_pc_lsb   = 1'b1;
      end

      riscv_pkg::OP_LUI: begin
        reg_write      = 1'b1;
        imm_src        = riscv_pkg::IMM_U;
        alu_result_src = riscv_pkg::ALU_RES_IMM;  // the ALU is not used at all
      end

      riscv_pkg::OP_AUIPC: begin
        reg_write      = 1'b1;
        imm_src        = riscv_pkg::IMM_U;
        alu_src        = riscv_pkg::ALU_SRC_PC_IMM;  // pc + imm, computed by the ALU
        alu_result_src = riscv_pkg::ALU_RES_ALU;
      end

      // ecall/ebreak are not implemented; they fall through to the safe
      // defaults, same as an illegal opcode.
      riscv_pkg::OP_SYSTEM: begin
        illegal_main = 1'b1;
      end

      riscv_pkg::OP_FENCE: begin
        illegal_main = 1'b0;
      end

      default: begin
        illegal_main = 1'b1;
      end
    endcase

    if ((instr.r.opcode == riscv_pkg::OP_LOAD) || (instr.r.opcode == riscv_pkg::OP_STORE)) begin
      // Invalid store funct3 values are not trapped yet; illegal-instruction handling
      // will tighten this later.
      unique case (instr.r.funct3.mem)
        riscv_pkg::MEM_BYTE: begin
          mem_size = riscv_pkg::MEM_SIZE_BYTE;
          mem_unsigned = 1'b0;
        end
        riscv_pkg::MEM_HALF: begin
          mem_size = riscv_pkg::MEM_SIZE_HALF;
          mem_unsigned = 1'b0;
        end
        riscv_pkg::MEM_WORD: begin
          mem_size = riscv_pkg::MEM_SIZE_WORD;
          mem_unsigned = 1'b0;
        end
        riscv_pkg::MEM_BYTEU: begin
          mem_size     = riscv_pkg::MEM_SIZE_BYTE;
          mem_unsigned = instr.r.opcode == riscv_pkg::OP_LOAD ? 1'b1 : 1'b0;
        end
        riscv_pkg::MEM_HALFU: begin
          mem_size     = riscv_pkg::MEM_SIZE_HALF;
          mem_unsigned = instr.r.opcode == riscv_pkg::OP_LOAD ? 1'b1 : 1'b0;
        end
      endcase
    end
  end

endmodule
