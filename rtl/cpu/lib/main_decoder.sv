`timescale 1ns / 1ps

// Main decoder: a pure function of instr[6:0], the opcode.
//
// A direct transcription of the Wally main-decoder table, restricted to RV32I
// -- the W64 column and the RW/IW-type rows drop out, since RV32I has no *W
// instructions.
//
//   category op      branch jump alu_operands imm_format execute_result writeback_result alu_decode_en reg_write_en mem_write_en
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
  input  instr_u            instr,
  output logic              reg_write_en,
  output logic              mem_write_en,
  output imm_format_t       imm_format,
  output alu_operands_t     alu_operands,
  output execute_result_t   execute_result,
  output writeback_result_t writeback_result,
  output flow_t             flow,
  output logic              alu_decode_en,
  output logic              clear_pc_lsb,
  output logic              main_op_illegal
);

  always_comb begin
    // Defaults fail safe: an opcode this decoder does not recognise commits
    // nothing -- no register write, no memory write, no change of control flow.
    reg_write_en     = 1'b0;
    imm_format       = IMM_I;
    mem_write_en     = 1'b0;
    alu_operands     = ALU_OPERANDS_RS1_RS2;
    execute_result   = EXEC_RESULT_ALU;
    writeback_result = WB_RESULT_EXEC;
    flow             = FLOW_NONE;
    alu_decode_en    = 1'b0;
    clear_pc_lsb     = 1'b0;
    main_op_illegal  = 1'b0;

    case (instr.r.opcode)
      OP_R: begin
        reg_write_en  = 1'b1;
        alu_decode_en = 1'b1;  // operation comes from funct3/funct7
      end

      OP_I_ALU: begin
        reg_write_en = 1'b1;
        imm_format = IMM_I;
        alu_operands = ALU_OPERANDS_RS1_IMM;
        alu_decode_en = 1'b1;
      end

      OP_LOAD: begin
        reg_write_en  = 1'b1;
        imm_format    = IMM_I;
        alu_operands    = ALU_OPERANDS_RS1_IMM;  // address = rs1 + imm
        writeback_result = WB_RESULT_MEM;   // rd gets the loaded value, not the address
      end

      OP_STORE: begin
        mem_write_en = 1'b1;
        imm_format   = IMM_S;
        alu_operands = ALU_OPERANDS_RS1_IMM;  // address = rs1 + imm; rs2 is the store data
      end

      OP_BRANCH: begin
        flow = FLOW_BRANCH;
        imm_format = IMM_B;
        // The ALU computes the target; a separate comparator decides whether
        // the branch is taken.
        alu_operands = ALU_OPERANDS_PC_IMM;
      end

      OP_JAL: begin
        flow           = FLOW_JUMP;
        reg_write_en   = 1'b1;
        imm_format     = IMM_J;
        alu_operands   = ALU_OPERANDS_PC_IMM;  // target = pc + imm
        execute_result = EXEC_RESULT_PC_PLUS4;  // but rd gets the return address
      end

      OP_JALR: begin
        flow           = FLOW_JUMP;
        reg_write_en   = 1'b1;
        imm_format     = IMM_I;  // I-type, not J-type
        alu_operands   = ALU_OPERANDS_RS1_IMM;  // target = rs1 + imm
        execute_result = EXEC_RESULT_PC_PLUS4;
        clear_pc_lsb   = 1'b1;
      end

      OP_LUI: begin
        reg_write_en   = 1'b1;
        imm_format     = IMM_U;
        execute_result = EXEC_RESULT_IMM;  // the ALU is not used at all
      end

      OP_AUIPC: begin
        reg_write_en   = 1'b1;
        imm_format     = IMM_U;
        alu_operands   = ALU_OPERANDS_PC_IMM;  // pc + imm, computed by the ALU
        execute_result = EXEC_RESULT_ALU;
      end

      OP_FENCE, OP_SYSTEM: begin
        main_op_illegal = 1'b0;
      end

      default: begin
        main_op_illegal = 1'b1;
      end
    endcase
  end

endmodule
