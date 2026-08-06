`timescale 1ns / 1ps

module trap_control
  import riscv_pkg::*;
(

  input trap_req_t  trap_req,
  input pc_t        pc,
  /* verilator lint_off UNUSEDSIGNAL */
  input mtvec_t     mtvec,
  /* verilator lint_on UNUSEDSIGNAL */
  input priv_mode_t priv_mode,

  output trap_stage_t trap
);
  localparam logic [30:0] MACHINE_SOFTWARE_INTERRUPT_CODE = 31'd3;
  localparam logic [30:0] MACHINE_TIMER_INTERRUPT_CODE    = 31'd7;
  localparam logic [30:0] MACHINE_EXTERNAL_INTERRUPT_CODE = 31'd11;

  pc_t _base_trap_pc;
  pc_t _vec_trap_pc;

  always_comb begin
    _base_trap_pc = {mtvec.base, 2'b00};
    trap.payload = '0;
    trap.valid = trap_req.valid;
    trap.payload.mtval = trap_req.mtval;
    trap.payload.mepc = pc;
    trap.payload.pc = _base_trap_pc;

    // Compute cause/mcval from trap request source.
    // slang lint_off case-enum-explicit
    case (trap_req.src)
      TRAP_SRC_INSTR_ADDR_MISALIGNED: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_INSTR_ADDR_MISALIGNED};
      end
      TRAP_SRC_ILLEGAL_INSTR: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
      end
      TRAP_SRC_ILLEGAL_CSR: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR};
      end
      TRAP_SRC_ECALL: begin
        trap.payload.mcause.is_interrupt = 1'b0;
        unique case (priv_mode)
          PRIV_USER: begin
            trap.payload.mcause.code = MCAUSE_ECALL_U;
          end
          PRIV_SUPERVISOR: begin
            trap.payload.mcause.code = MCAUSE_ECALL_S;
          end
          PRIV_MACHINE: begin
            trap.payload.mcause.code = MCAUSE_ECALL_M;
          end
          default: begin
            trap.payload.mcause.code = MCAUSE_ECALL_M;
          end
        endcase
      end
      TRAP_SRC_EBREAK: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_BREAKPOINT};
      end
      TRAP_SRC_MACHINE_SOFTWARE_INTERRUPT: begin
        trap.payload.mcause = '{is_interrupt: 1'b1, code: exception_code_t'(MACHINE_SOFTWARE_INTERRUPT_CODE)};
      end
      TRAP_SRC_MACHINE_TIMER_INTERRUPT: begin
        trap.payload.mcause = '{is_interrupt: 1'b1, code: exception_code_t'(MACHINE_TIMER_INTERRUPT_CODE)};
      end
      TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT: begin
        trap.payload.mcause = '{is_interrupt: 1'b1, code: exception_code_t'(MACHINE_EXTERNAL_INTERRUPT_CODE)};
      end
      TRAP_SRC_LOAD_ADDR_MISALIGNED: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_LOAD_ADDR_MISALIGNED};
      end
      TRAP_SRC_STORE_ADDR_MISALIGNED: begin
        trap.payload.mcause = '{is_interrupt: 1'b0, code: MCAUSE_STORE_ADDR_MISALIGNED};
      end
      default: begin
      end
    endcase
    // slang lint_on case-enum-explicit

    _vec_trap_pc = _base_trap_pc;
    if (mtvec.mode == MTVEC_MODE_VECTORED && trap.payload.mcause.is_interrupt) begin
      _vec_trap_pc = _base_trap_pc + (pc_t'(trap.payload.mcause.code) << 2);
    end

    if (trap.valid) begin
      trap.payload.pc = _vec_trap_pc;
    end
  end

endmodule
