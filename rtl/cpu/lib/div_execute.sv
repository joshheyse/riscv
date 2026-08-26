`timescale 1ns / 1ps

// RV32M integer divider/remainder executor.
//
// Signed division truncates its quotient toward zero. Its remainder has the
// sign of the dividend (`src_a`) when nonzero. DIVU and REMU interpret both
// operands as unsigned. None of the architecturally defined corner cases trap.
//
//   div_op                    operands  div_result
//   ------------------------  --------  ------------------
//   DIV_OP_QUOTIENT_SIGNED    signed    src_a / src_b
//   DIV_OP_QUOTIENT_UNSIGNED  unsigned  src_a / src_b
//   DIV_OP_REMAINDER_SIGNED   signed    src_a % src_b
//   DIV_OP_REMAINDER_UNSIGNED unsigned  src_a % src_b
//
//   corner case                         quotient             remainder
//   ----------------------------------  -------------------  ----------------
//   src_b == 0                          32'hffff_ffff         src_a
//   signed 32'h8000_0000 / 32'hffff_ffff 32'h8000_0000       32'h0000_0000
//
// This port list expresses the architectural operation and result only. An
// iterative implementation will also need a pipeline-visible request/completion
// contract so its operands are accepted once and its result is consumed once.
//
module div_execute
  import riscv_pkg::*;
(
  input  integer_data_t src_a,
  input  integer_data_t src_b,
  input  div_op_t       div_op,
  output integer_data_t div_result
);

  localparam integer_data_t MinSigned = 32'h8000_0000;
  localparam integer_data_t NegOne = 32'hffff_ffff;

  always_comb begin
    div_result = '0;
    if (src_b == '0) begin
      case (div_op)
        DIV_OP_QUOTIENT_SIGNED, DIV_OP_QUOTIENT_UNSIGNED:   div_result = '1;
        DIV_OP_REMAINDER_SIGNED, DIV_OP_REMAINDER_UNSIGNED: div_result = src_a;
        default: begin
        end
      endcase
    end else if (src_a == MinSigned && src_b == NegOne &&
                 (div_op == DIV_OP_QUOTIENT_SIGNED || div_op == DIV_OP_REMAINDER_SIGNED)) begin
      div_result = div_op == DIV_OP_QUOTIENT_SIGNED ? MinSigned : '0;
    end else begin
      case (div_op)
        DIV_OP_QUOTIENT_SIGNED: begin
          div_result = $unsigned($signed(src_a) / $signed(src_b));
        end
        DIV_OP_QUOTIENT_UNSIGNED: begin
          div_result = $unsigned(src_a) / $unsigned(src_b);
        end
        DIV_OP_REMAINDER_SIGNED: begin
          div_result = $unsigned($signed(src_a) % $signed(src_b));
        end
        DIV_OP_REMAINDER_UNSIGNED: begin
          div_result = $unsigned(src_a) % $unsigned(src_b);
        end
        default: begin
        end
      endcase
    end
  end

endmodule
