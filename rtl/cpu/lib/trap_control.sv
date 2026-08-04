`timescale 1ns / 1ps

module trap_control
  import riscv_pkg::*;
(

  input logic   illegal_instr,
  input instr_u instr,
  input pc_t    pc,
  input mtvec_t mtvec,

  output trap_t trap
);

  assign trap.valid  = illegal_instr;
  assign trap.mepc   = pc;
  assign trap.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
  assign trap.mtval  = instr.raw;
  assign trap.pc     = {mtvec.base, 2'b00};

  logic _unused_mtvec_mode;
  assign _unused_mtvec_mode = |mtvec.mode;

endmodule
