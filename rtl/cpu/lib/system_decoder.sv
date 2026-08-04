`timescale 1ns / 1ps

module system_decoder
  import riscv_pkg::*;
(
  input instr_u instr,

  output csr_ctrl_t    csr_ctrl,
  output system_ctrl_t system_ctrl
);

  always_comb begin
    csr_ctrl = '{en: 1'b0, write_en: 1'b0, op: CSR_OP_RW, use_zimm: 1'b0};
    system_ctrl = '0;
    system_ctrl.en = instr.r.opcode == OP_SYSTEM;

    if (instr.r.opcode == OP_SYSTEM) begin
      case (instr.r.funct3.sys)
        SYS_F3_PRIV: begin
          system_ctrl.illegal = 1'b1;
        end
        SYS_F3_RW: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = 1'b1;
          csr_ctrl.op = CSR_OP_RW;
          csr_ctrl.use_zimm = 1'b0;
        end
        SYS_F3_RS: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = instr.r.rs1 != 5'd0;
          csr_ctrl.op = CSR_OP_RS;
          csr_ctrl.use_zimm = 1'b0;
        end
        SYS_F3_RC: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = instr.r.rs1 != 5'd0;
          csr_ctrl.op = CSR_OP_RC;
          csr_ctrl.use_zimm = 1'b0;
        end
        SYS_F3_RWI: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = 1'b1;
          csr_ctrl.op = CSR_OP_RW;
          csr_ctrl.use_zimm = 1'b1;
        end
        SYS_F3_RSI: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = instr.r.rs1 != 5'd0;
          csr_ctrl.op = CSR_OP_RS;
          csr_ctrl.use_zimm = 1'b1;
        end
        SYS_F3_RCI: begin
          csr_ctrl.en = 1'b1;
          csr_ctrl.write_en = instr.r.rs1 != 5'd0;
          csr_ctrl.op = CSR_OP_RC;
          csr_ctrl.use_zimm = 1'b1;
        end
        default: begin
          system_ctrl.illegal = 1'b1;
        end
      endcase
    end
  end

endmodule
