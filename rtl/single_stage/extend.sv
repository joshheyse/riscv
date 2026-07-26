`timescale 1ns / 1ps

module extend
  import riscv_pkg::*;
(
  input imm_src_t imm_src,
  input logic [31:7] instr,
  output word_t imm_ext
);

  always_comb begin
    imm_ext = 'x;
    unique case (imm_src)
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
