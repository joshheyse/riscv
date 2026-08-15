`timescale 1ns / 1ps

module system_decoder
  import riscv_pkg::*;
(
  input instr_u instr,

  output csr_ctrl_t    csr_ctrl,
  output system_ctrl_t system_ctrl
);

  /*
  2. System instruction privilege checks
      - mret should only be legal in machine mode.
      - sret is legal in supervisor or machine mode; mstatus.TSR can block it
        in supervisor mode.
      - wfi can stay illegal/unimplemented for now.
*/

  logic _priv_fields_valid;

  always_comb begin
    csr_ctrl = '{en: 1'b0, write_en: 1'b0, op: CSR_OP_RW, use_zimm: 1'b0};
    system_ctrl = '{en: 1'b0, op: SYSTEM_OP_NONE};
    system_ctrl.en = instr.r.opcode == OP_SYSTEM;

    _priv_fields_valid = (instr.r.rs1 == 5'd0) && (instr.r.rd == 5'd0);

    if (instr.r.opcode == OP_SYSTEM) begin
      case (instr.r.funct3.sys)
        SYS_F3_PRIV: begin
          if (!_priv_fields_valid) begin
            system_ctrl.op = SYSTEM_OP_ILLEGAL;
          end else begin
            case (instr.i.imm.sys)
              SYS_IMM_MRET: begin
                system_ctrl.op = SYSTEM_OP_MRET;
              end
              SYS_IMM_SRET: begin
                system_ctrl.op = SYSTEM_OP_SRET;
              end
              SYS_IMM_ECALL: begin
                system_ctrl.op = SYSTEM_OP_ECALL;
              end
              SYS_IMM_EBREAK: begin
                system_ctrl.op = SYSTEM_OP_EBREAK;
              end
              SYS_IMM_WFI: begin
                system_ctrl.op = SYSTEM_OP_WFI;
              end
              default: begin
                system_ctrl.op = SYSTEM_OP_ILLEGAL;
              end
            endcase
          end
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
          system_ctrl.op = SYSTEM_OP_ILLEGAL;
        end
      endcase
    end
  end

endmodule
