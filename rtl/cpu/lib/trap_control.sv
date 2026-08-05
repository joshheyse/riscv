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

  always_comb begin
    trap.valid         = trap_ctrl.valid;
    trap.payload.mtval = '0;
    trap.payload.mepc  = pc;
    trap.payload.pc    = {mtvec.base, 2'b00};
    case (trap_ctrl.src)
      TRAP_SRC_ILLEGAL_INSTR: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
        trap.payload.mtval  = instr.raw;
      end
      TRAP_SRC_ECALL: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ECALL_M};
      end
      TRAP_SRC_EBREAK: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_BREAKPOINT};
      end
      default: begin
        trap.payload = '0;
      end
    endcase
  end

  logic _unused_mtvec_mode;
  assign _unused_mtvec_mode = |mtvec.mode;

endmodule
