`timescale 1ns / 1ps

// RV32M integer multiplier.
//
// Every operation forms a full 64-bit product from the two 32-bit operands,
// then selects either its low or high word. MUL's low word is identical for
// signed and unsigned multiplication; the high-word operations must extend
// each operand with the signedness shown below before multiplying.
//
//   mul_op          src_a       src_b       mul_result
//   --------------  ----------  ----------  -----------------------
//   MUL_OP_LOW      either      either      product[31:0]
//   MUL_OP_HIGH_SS  signed      signed      product[63:32]
//   MUL_OP_HIGH_SU  signed      unsigned    product[63:32]
//   MUL_OP_HIGH_UU  unsigned    unsigned    product[63:32]
//
// The architectural result is always one 32-bit word. A wider product type is
// therefore an implementation detail rather than part of this module's
// interface.
//
module mul_execute
  import riscv_pkg::*;
(
  input  integer_data_t src_a,
  input  integer_data_t src_b,
  input  mul_op_t       mul_op,
  output integer_data_t mul_result
);

  logic signed [63:0] product;
  logic signed [63:0] a;
  logic signed [63:0] b;

  always_comb begin
    mul_result = '0;
    product = '0;
    a = $signed({{32{src_a[31]}}, src_a});
    b = $signed({32'b0, src_b});
    case (mul_op)
      MUL_OP_LOW: begin
        product = a * b;
        mul_result = product[31:0];
      end
      MUL_OP_HIGH_SS, MUL_OP_HIGH_SU, MUL_OP_HIGH_UU: begin
        if (mul_op == MUL_OP_HIGH_SS) begin
          b = $signed({{32{src_b[31]}}, src_b});
        end else if (mul_op == MUL_OP_HIGH_UU) begin
          a = $signed({32'b0, src_a});
        end
        product = a * b;
        mul_result = product[63:32];
      end
      default: begin
      end
    endcase
  end

endmodule
