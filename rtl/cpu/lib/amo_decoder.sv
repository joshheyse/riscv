`timescale 1ns / 1ps

// Atomic-memory-operation decoder.
//
// OP-AMO uses funct3=010 for every RV32A word operation. Bits [31:27]
// (`funct5`) select the operation, while bits 26 and 25 independently request
// acquire and release ordering. LR.W is the only operation that requires a
// particular rs2 encoding: rs2 must be x0.
//
//   instruction  opcode  funct5  funct3  rs2       amo_ctrl.op
//   -----------  ------  ------  ------  --------  -----------
//   amoadd.w     OP_AMO  00000   010     any       AMO_OP_ADD
//   amoswap.w    OP_AMO  00001   010     any       AMO_OP_SWAP
//   lr.w         OP_AMO  00010   010     x0        AMO_OP_LR
//   sc.w         OP_AMO  00011   010     any       AMO_OP_SC
//   amoxor.w     OP_AMO  00100   010     any       AMO_OP_XOR
//   amoor.w      OP_AMO  01000   010     any       AMO_OP_OR
//   amoand.w     OP_AMO  01100   010     any       AMO_OP_AND
//   amomin.w     OP_AMO  10000   010     any       AMO_OP_MIN
//   amomax.w     OP_AMO  10100   010     any       AMO_OP_MAX
//   amominu.w    OP_AMO  11000   010     any       AMO_OP_MINU
//   amomaxu.w    OP_AMO  11100   010     any       AMO_OP_MAXU
//
// Any other funct5, a funct3 other than 010, or LR.W with rs2 != x0 is an
// illegal instruction. The aq/rl bits do not affect operation selection and
// all four combinations are legal.
//
module amo_decoder
  import riscv_pkg::*;
(
  input  logic      amo_decode_en,
  input  instr_u    instr,
  output amo_ctrl_t amo_ctrl,
  output logic      amo_op_illegal
);

  always_comb begin
    amo_ctrl.en = amo_decode_en;
    amo_ctrl.op = instr.amo.op;
    amo_ctrl.aq = instr.amo.aq;
    amo_ctrl.rl = instr.amo.rl;
    amo_op_illegal = 1'b0;

    if (amo_decode_en) begin
      if (instr.amo.opcode != OP_AMO || instr.amo.funct3 != AMO_F3_WORD) begin
        amo_op_illegal = 1'b1;
      end else begin
        case (instr.amo.op)
          AMO_OP_LR: begin
            amo_op_illegal = instr.amo.rs2 != '0;
          end
          AMO_OP_ADD, AMO_OP_SWAP, AMO_OP_SC, AMO_OP_XOR, AMO_OP_OR, AMO_OP_AND, AMO_OP_MIN,
              AMO_OP_MAX, AMO_OP_MINU, AMO_OP_MAXU: begin
          end
          default: amo_op_illegal = 1'b1;
        endcase
      end
    end
  end

endmodule
