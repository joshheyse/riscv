`timescale 1ns / 1ps

// RV32I integer ALU.
//
// `alu_op` is intentionally the RV32I OP/OP-IMM funct3 encoding, so most
// operations decode directly. `sub_arith` supplies the one extra funct7 bit
// needed to distinguish add/sub and srl/sra.
//
//   alu_op  sub_arith=0       sub_arith=1
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
  input  alu_data_t src_a,
  input  alu_data_t src_b,
  input  alu_op_t   alu_op,
  input  wire       sub_arith,
  output alu_data_t alu_result
);

  alu_data_t _add;
  alu_data_t _sub;
  alu_data_t _and;
  alu_data_t _or;
  alu_data_t _xor;
  assign _add = src_a + src_b;
  assign _sub = src_a - src_b;
  assign _and = src_a & src_b;
  assign _or  = src_a | src_b;
  assign _xor = src_a ^ src_b;

  alu_data_t _arith;
  assign _arith = $unsigned($signed(src_a) >>> src_b[4:0]);


  always_comb begin
    unique case (alu_op)
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
