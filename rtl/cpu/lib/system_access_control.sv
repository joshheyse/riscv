`timescale 1ns / 1ps

module system_access_control
  import riscv_pkg::*;
(
  input  system_ctrl_t system_ctrl,
  input  priv_mode_t   priv_mode,
  output logic         illegal_system_access
);

  always_comb begin
    illegal_system_access = 1'b0;
    if (system_ctrl.en) begin
      case (system_ctrl.op)
        SYSTEM_OP_MRET: illegal_system_access = priv_mode != PRIV_MACHINE;
        SYSTEM_OP_SRET: illegal_system_access = priv_mode == PRIV_USER;
        default: begin
        end
      endcase
    end
  end

endmodule
