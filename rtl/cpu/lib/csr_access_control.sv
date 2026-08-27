`timescale 1ns / 1ps

module csr_access_control
  import riscv_pkg::*;
(
  input  logic       csr_en,
  input  logic       csr_write_en,
  input  csr_addr_t  csr_addr,
  input  priv_mode_t priv_mode,
  /* verilator lint_off UNUSEDSIGNAL */
  input  counteren_t mcounteren,
  input  counteren_t scounteren,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic       illegal_csr_access
);

  function automatic logic counter_access_allowed(input priv_mode_t mode,
                                                   input logic       machine_enabled,
                                                   input logic       supervisor_enabled);
    case (mode)
      PRIV_MACHINE:    return 1'b1;
      PRIV_SUPERVISOR: return machine_enabled;
      PRIV_USER:       return machine_enabled && supervisor_enabled;
      default:         return 1'b0;
    endcase
  endfunction

  always_comb begin
    illegal_csr_access = 1'b0;

    if (csr_en) begin
      if (priv_mode < csr_addr.fields.min_priv) begin
        illegal_csr_access = 1'b1;
      end

      // slang lint_off case-enum-explicit
      case (csr_addr.named)
        CSR_CYCLE, CSR_CYCLEH: begin
          if (!counter_access_allowed(priv_mode, mcounteren.cy, scounteren.cy)) begin
            illegal_csr_access = 1'b1;
          end
        end
        CSR_TIME, CSR_TIMEH: begin
          if (!counter_access_allowed(priv_mode, mcounteren.tm, scounteren.tm)) begin
            illegal_csr_access = 1'b1;
          end
        end
        CSR_INSTRET, CSR_INSTRETH: begin
          if (!counter_access_allowed(priv_mode, mcounteren.ir, scounteren.ir)) begin
            illegal_csr_access = 1'b1;
          end
        end
        default: begin
        end
      endcase
      // slang lint_on case-enum-explicit

      if (csr_write_en) begin
        if (csr_addr.fields.rw == 2'b11) begin
          illegal_csr_access = 1'b1;
        end
      end
    end
  end

endmodule
