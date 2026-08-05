`timescale 1ns / 1ps

module trap_control
  import riscv_pkg::*;
(

  input trap_ctrl_t trap_ctrl,
  input instr_u     instr,
  input pc_t        pc,
  input mtvec_t     mtvec,

  output trap_stage_t trap
);

  assign trap.valid          = trap_ctrl.valid;
  assign trap.payload.mepc   = pc;
  assign trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
  assign trap.payload.mtval  = instr.raw;
  assign trap.payload.pc     = {mtvec.base, 2'b00};

  logic _unused_trap_src;
  assign _unused_trap_src = |trap_ctrl.src;

  logic _unused_mtvec_mode;
  assign _unused_mtvec_mode = |mtvec.mode;

endmodule
