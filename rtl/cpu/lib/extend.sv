`timescale 1ns / 1ps

// RV32I immediate extender.
//
// Input omits instr[6:0] because immediate generation never needs the opcode.
// The B/J immediates append an implicit zero LSB because branch/jump targets are
// at least halfword-aligned by the ISA encoding.
//
//   imm_format  source bits                         result shape
//   -------  ----------------------------------  -----------------------------
//   IMM_I    instr[31:20]                        sign-extend 12-bit immediate
//   IMM_S    instr[31:25], instr[11:7]           sign-extend 12-bit immediate
//   IMM_B    instr[31], [7], [30:25], [11:8], 0  sign-extend branch offset
//   IMM_J    instr[31], [19:12], [20], [30:21],0 sign-extend jump offset
//   IMM_U    instr[31:12], 12'b0                 upper immediate
//
module extend
  import riscv_pkg::*;
(
  input  imm_format_t        imm_format,
  input  logic        [31:7] instr,
  output imm_t               imm_ext
);

  always_comb begin
    imm_ext = 'x;
    unique case (imm_format)
      // verilog_format: off
      IMM_I: imm_ext = {{20{instr[31]}}, instr[31:20]};                                  // 12-bit signed
      IMM_S: imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};                     // 12-bit signed
      IMM_B: imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};     // 13-bit signed
      IMM_J: imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};   // 21-bit signed
      IMM_U: imm_ext = {instr[31:12], 12'b0};                                            // 20-bit signed
      // verilog_format: on
    endcase
  end

endmodule
