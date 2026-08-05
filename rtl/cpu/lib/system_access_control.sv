`timescale 1ns / 1ps

module system_access_control
  import riscv_pkg::*;
(
  input  system_ctrl_t system_ctrl,
  input  priv_mode_t   priv_mode,
  output logic         illegal_system_access
);

  assign illegal_system_access = system_ctrl.en && (system_ctrl.op == SYSTEM_OP_MRET)
                               && (priv_mode != PRIV_MACHINE);

endmodule
