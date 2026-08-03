`timescale 1ns / 1ps

module trap_controller
  import riscv_pkg::*;
(

  input logic   illegal_instr,
  input instr_u instr,
  input pc_t    pc,
  input mtvec_t mtvec,

  output logic    trap_valid,
  output mepc_t   trap_mepc,
  output mcause_t trap_mcause,
  output mtval_t  trap_mtval,
  output pc_t     trap_pc
);

  assign trap_valid  = illegal_instr;
  assign trap_mepc   = pc;
  assign trap_mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
  assign trap_mtval  = instr.raw;
  assign trap_pc     = {mtvec.base, 2'b00};

  logic _unused_mtvec_mode;
  assign _unused_mtvec_mode = |mtvec.mode;

endmodule
