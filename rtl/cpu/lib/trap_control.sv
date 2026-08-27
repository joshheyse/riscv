`timescale 1ns / 1ps

module trap_control
  import riscv_pkg::*;
(

  input trap_req_t   trap_req,
  input pc_t         pc,
  /* verilator lint_off UNUSEDSIGNAL */
  input csr_status_t csr_status,
  /* verilator lint_on UNUSEDSIGNAL */

  output trap_stage_t trap
);
  localparam logic [30:0] MACHINE_SOFTWARE_INTERRUPT_CODE = 31'd3;
  localparam logic [30:0] MACHINE_TIMER_INTERRUPT_CODE = 31'd7;
  localparam logic [30:0] MACHINE_EXTERNAL_INTERRUPT_CODE = 31'd11;
  localparam logic [30:0] SUPERVISOR_SOFTWARE_INTERRUPT_CODE = 31'd1;
  localparam logic [30:0] SUPERVISOR_TIMER_INTERRUPT_CODE = 31'd5;
  localparam logic [30:0] SUPERVISOR_EXTERNAL_INTERRUPT_CODE = 31'd9;

  pc_t _base_trap_pc;
  pc_t _vec_trap_pc;

  always_comb begin
    trap.payload = '0;
    trap.valid = trap_req.valid;
    trap.payload.tval = trap_req.tval;
    trap.payload.epc = pc;

    // Compute cause/tval from trap request source.
    // slang lint_off case-enum-explicit
    case (trap_req.src)
      TRAP_SRC_INSTR_ADDR_MISALIGNED: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_INSTR_ADDR_MISALIGNED};
      end
      TRAP_SRC_ILLEGAL_INSTR: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR};
      end
      TRAP_SRC_ILLEGAL_CSR: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR};
      end
      TRAP_SRC_ECALL: begin
        trap.payload.cause.is_interrupt = 1'b0;
        unique case (csr_status.priv_mode)
          PRIV_USER: begin
            trap.payload.cause.code = CAUSE_ECALL_U;
          end
          PRIV_SUPERVISOR: begin
            trap.payload.cause.code = CAUSE_ECALL_S;
          end
          PRIV_MACHINE: begin
            trap.payload.cause.code = CAUSE_ECALL_M;
          end
          default: begin
            trap.payload.cause.code = CAUSE_ECALL_M;
          end
        endcase
      end
      TRAP_SRC_EBREAK: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT};
      end
      TRAP_SRC_MACHINE_SOFTWARE_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(MACHINE_SOFTWARE_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_MACHINE_TIMER_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(MACHINE_TIMER_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(MACHINE_EXTERNAL_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(SUPERVISOR_SOFTWARE_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_SUPERVISOR_TIMER_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(SUPERVISOR_TIMER_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_SUPERVISOR_EXTERNAL_INTERRUPT: begin
        trap.payload.cause = '{
            is_interrupt: 1'b1,
            code: cause_code_e'(SUPERVISOR_EXTERNAL_INTERRUPT_CODE)
        };
      end
      TRAP_SRC_LOAD_ADDR_MISALIGNED: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_LOAD_ADDR_MISALIGNED};
      end
      TRAP_SRC_STORE_ADDR_MISALIGNED: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_STORE_ADDR_MISALIGNED};
      end
      TRAP_SRC_INSTR_ACCESS_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_INSTR_ACCESS_FAULT};
      end
      TRAP_SRC_LOAD_ACCESS_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_LOAD_ACCESS_FAULT};
      end
      TRAP_SRC_STORE_ACCESS_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_STORE_ACCESS_FAULT};
      end
      TRAP_SRC_INSTR_PAGE_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_INSTR_PAGE_FAULT};
      end
      TRAP_SRC_LOAD_PAGE_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_LOAD_PAGE_FAULT};
      end
      TRAP_SRC_STORE_PAGE_FAULT: begin
        trap.payload.cause = '{is_interrupt: 1'b0, code: CAUSE_STORE_PAGE_FAULT};
      end
      default: begin
      end
    endcase
    // slang lint_on case-enum-explicit

    trap.payload.target_priv = PRIV_MACHINE;
    if (int'(trap.payload.cause.code) < 32) begin
      if (csr_status.priv_mode != PRIV_MACHINE) begin
        if (trap.payload.cause.is_interrupt) begin
          if (csr_status.mideleg[trap.payload.cause.code[4:0]]) begin
            trap.payload.target_priv = PRIV_SUPERVISOR;
          end
        end else begin
          if (csr_status.medeleg[trap.payload.cause.code[4:0]]) begin
            trap.payload.target_priv = PRIV_SUPERVISOR;
          end
        end
      end
    end

    _base_trap_pc = {
      trap.payload.target_priv == PRIV_MACHINE ? csr_status.mtvec.base : csr_status.stvec.base,
      2'b00
    };
    trap.payload.handler_pc = _base_trap_pc;

    _vec_trap_pc = _base_trap_pc;
    if ((
      (trap.payload.target_priv == PRIV_MACHINE && csr_status.mtvec.mode == TVEC_MODE_VECTORED) ||
      (trap.payload.target_priv == PRIV_SUPERVISOR && csr_status.stvec.mode == TVEC_MODE_VECTORED)
      ) && trap.payload.cause.is_interrupt) begin
      _vec_trap_pc = _base_trap_pc + (pc_t'(trap.payload.cause.code) << 2);
    end

    if (trap.valid) begin
      trap.payload.handler_pc = _vec_trap_pc;
    end
  end

endmodule
