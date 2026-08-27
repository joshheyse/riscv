`timescale 1ns / 1ps

// Multiply/divide decoder.
//
// The main decoder first identifies an RV32M instruction
// (`muldiv_decode_en=1`). RV32M uses the OP opcode with funct7=0000001;
// funct3 selects both the execution unit and the result variant. In
// particular, funct3[2] selects the unit: 0 for multiply and 1 for
// divide/remainder.
//
//   instruction  opcode  funct7  funct3  execution unit  result
//   -----------  ------  -------  ------  --------------  --------------------------
//   mul          OP_R    0000001  000     multiply        product[31:0]
//   mulh         OP_R    0000001  001     multiply        signed product[63:32]
//   mulhsu       OP_R    0000001  010     multiply        signed*unsigned product[63:32]
//   mulhu        OP_R    0000001  011     multiply        unsigned product[63:32]
//   div          OP_R    0000001  100     divide          signed quotient
//   divu         OP_R    0000001  101     divide          unsigned quotient
//   rem          OP_R    0000001  110     divide          signed remainder
//   remu         OP_R    0000001  111     divide          unsigned remainder
//
module muldiv_decoder
  import riscv_pkg::*;
(
  input  logic         muldiv_decode_en,
  input  instr_u       instr,
  output muldiv_ctrl_t muldiv_ctrl
);

  assign muldiv_ctrl.unit = instr.r.funct3[2] ? MULDIV_DIV : MULDIV_MUL;
  assign muldiv_ctrl.mul_op = mul_op_e'(instr.r.funct3[1:0]);
  assign muldiv_ctrl.div_op = div_op_e'(instr.r.funct3[1:0]);
  assign muldiv_ctrl.en = muldiv_decode_en;

endmodule
