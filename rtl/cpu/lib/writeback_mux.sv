`timescale 1ns / 1ps

// Selects the value written to the integer register file.
module writeback_mux
  import riscv_pkg::*;
(
  input result_src_t result_src,
  input reg_data_t   execute_result,
  input mem_data_t   read_data,

  output reg_data_t writeback_data
);

  always_comb begin
    unique case (result_src)
      RESULT_ALU: writeback_data = execute_result;
      RESULT_MEM: writeback_data = read_data;
    endcase
  end

endmodule
