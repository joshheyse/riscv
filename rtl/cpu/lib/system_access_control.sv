`timescale 1ns / 1ps

module system_access_control
  import riscv_pkg::*;
(
  input  system_ctrl_t system_ctrl,
  input  priv_mode_e   priv_mode,
  input  logic         tsr,
  input  logic         tvm,
  output logic         illegal_system_access
);

  always_comb begin
    illegal_system_access = 1'b0;
    if (system_ctrl.en) begin
      case (system_ctrl.op)
        SYSTEM_OP_MRET: begin
          illegal_system_access = priv_mode != PRIV_MACHINE;
        end
        SYSTEM_OP_SFENCE_VMA: begin
          illegal_system_access = (priv_mode == PRIV_USER) || (priv_mode == PRIV_SUPERVISOR && tvm);
        end
        SYSTEM_OP_SRET: begin
          illegal_system_access = (priv_mode == PRIV_USER) || ((priv_mode == PRIV_SUPERVISOR) && tsr);
        end
        default: begin
        end
      endcase
    end
  end

endmodule
