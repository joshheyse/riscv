`timescale 1ns / 1ps

// Selects the value written to the integer register file.
module writeback_mux
  import riscv_pkg::*;
(
  input writeback_result_t writeback_result,
  input reg_data_t         execute_result,
  input mem_data_t         read_data,

  output reg_data_t writeback_data
);

  always_comb begin
    unique case (writeback_result)
      WB_RESULT_EXEC: writeback_data = execute_result;
      WB_RESULT_MEM:  writeback_data = read_data;
    endcase
  end

endmodule
