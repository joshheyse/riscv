`timescale 1ns / 1ps

module csr_execute
  import riscv_pkg::*;
(
  input  csr_op_t   csr_op,
  input  logic      csr_use_zimm,
  input  csr_data_t csr_read_data,
  input  reg_data_t rs1_data,
  input  csr_zimm_t zimm,
  output csr_data_t csr_result,
  output csr_data_t csr_write_data
);

  csr_data_t _write_data;

  always_comb begin
    csr_result  = csr_read_data;
    _write_data = csr_use_zimm ? {{(XLEN - 5) {1'b0}}, zimm} : rs1_data;

    case (csr_op)
      CSR_OP_RW: begin
        csr_write_data = _write_data;
      end
      CSR_OP_RS: begin
        csr_write_data = csr_read_data | _write_data;
      end
      CSR_OP_RC: begin
        csr_write_data = csr_read_data & ~(_write_data);
      end
      default: begin
        csr_write_data = '0;
        csr_result = '0;
      end
    endcase
  end

endmodule
