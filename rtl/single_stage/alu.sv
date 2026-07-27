`timescale 1ns / 1ps

// RV32I integer ALU.
//
// `alu_select` is intentionally the RV32I OP/OP-IMM funct3 encoding, so most
// operations decode directly. `sub_arith` supplies the one extra funct7 bit
// needed to distinguish add/sub and srl/sra.
//
//   alu_select  sub_arith=0       sub_arith=1
//   ----------  ----------------  ----------------
//   ADDSUB      src_a + src_b     src_a - src_b
//   SLL         src_a << shamt    same
//   SLT         signed less-than  same
//   SLTU        unsigned lt       same
//   XOR         bitwise xor       same
//   SRL_SRA     logical right     arithmetic right
//   OR          bitwise or        same
//   AND         bitwise and       same
//
module alu
  import riscv_pkg::*;
(
  input word_t src_a,
  input word_t src_b,
  input alu_select_t alu_select,
  input wire sub_arith,
  output word_t alu_result
);

  word_t _add;
  word_t _sub;
  word_t _and;
  word_t _or;
  word_t _xor;
  assign _add = src_a + src_b;
  assign _sub = src_a - src_b;
  assign _and = src_a & src_b;
  assign _or  = src_a | src_b;
  assign _xor = src_a ^ src_b;

  word_t _arith;
  assign _arith = $unsigned($signed(src_a) >>> src_b[4:0]);


  always_comb begin
    unique case (alu_select)
      ALU_ADDSUB:  alu_result = sub_arith == 'b0 ? _add : _sub;
      ALU_SLL:     alu_result = src_a << src_b[4:0];
      ALU_SLT:     alu_result = ($signed(src_a) < $signed(src_b)) ? 32'b1 : 32'b0;
      ALU_SLTU:    alu_result = (src_a < src_b) ? 32'b1 : 32'b0;
      ALU_XOR:     alu_result = _xor;
      ALU_SRL_SRA: alu_result = sub_arith ? _arith : (src_a >> src_b[4:0]);
      ALU_OR:      alu_result = _or;
      ALU_AND:     alu_result = _and;
    endcase
  end

endmodule
