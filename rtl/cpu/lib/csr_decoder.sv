`timescale 1ns / 1ps

module csr_decoder
  import riscv_pkg::*;
(
  input instr_u instr,

  output logic    csr_en,
  output logic    csr_write_en,
  output csr_op_t csr_op,
  output logic    csr_use_zimm,
  output logic    csr_op_illegal
);

  always_comb begin
    csr_en         = 1'b0;
    csr_write_en   = 1'b0;
    csr_op         = CSR_OP_RW;
    csr_use_zimm   = 1'b0;
    csr_op_illegal = 1'b0;

    if (instr.r.opcode == OP_SYSTEM) begin
      case (instr.r.funct3.csr)
        CSR_F3_PRIV: begin
          csr_op_illegal = 1'b1;
        end
        CSR_F3_RW: begin
          csr_en = 1'b1;
          csr_write_en = 1'b1;
          csr_op = CSR_OP_RW;
          csr_use_zimm = 1'b0;
        end
        CSR_F3_RS: begin
          csr_en = 1'b1;
          csr_write_en = instr.r.rs1 != 5'd0;
          csr_op = CSR_OP_RS;
          csr_use_zimm = 1'b0;
        end
        CSR_F3_RC: begin
          csr_en = 1'b1;
          csr_write_en = instr.r.rs1 != 5'd0;
          csr_op = CSR_OP_RC;
          csr_use_zimm = 1'b0;
        end
        CSR_F3_RWI: begin
          csr_en = 1'b1;
          csr_write_en = 1'b1;
          csr_op = CSR_OP_RW;
          csr_use_zimm = 1'b1;
        end
        CSR_F3_RSI: begin
          csr_en = 1'b1;
          csr_write_en = instr.r.rs1 != 5'd0;
          csr_op = CSR_OP_RS;
          csr_use_zimm = 1'b1;
        end
        CSR_F3_RCI: begin
          csr_en = 1'b1;
          csr_write_en = instr.r.rs1 != 5'd0;
          csr_op = CSR_OP_RC;
          csr_use_zimm = 1'b1;
        end
        default: begin
          csr_op_illegal = 1'b1;
        end
      endcase
    end
  end

endmodule
