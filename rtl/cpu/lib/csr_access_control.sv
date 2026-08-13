`timescale 1ns / 1ps

module csr_access_control
  import riscv_pkg::*;
(
  input  logic       csr_en,
  input  logic       csr_write_en,
  input  csr_addr_t  csr_addr,
  input  priv_mode_t priv_mode,
  output logic       illegal_csr_access
);

  always_comb begin
    illegal_csr_access = 1'b0;

    if (csr_en) begin
      if (priv_mode < csr_addr.fields.min_priv) begin
        illegal_csr_access = 1'b1;
      end

      if (csr_write_en) begin
        if (csr_addr.fields.rw == 2'b11) begin
          illegal_csr_access = 1'b1;
        end
      end
    end
  end

endmodule
