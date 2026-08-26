`timescale 1ns / 1ps

// Selects the pre-memory result produced by the execute stage.
//
// Loads still pass through this path with EXEC_RESULT_ALU: the ALU result is the
// load address. The final writeback mux later replaces it with memory read data.
module execute_result_mux
  import riscv_pkg::*;
(
  input execute_result_t execute_result_kind,
  input pc_t             pc,
  input imm_t            imm,
  input integer_data_t   alu_result,
  input csr_data_t       csr_result,

  output reg_data_t execute_result
);

  always_comb begin
    unique case (execute_result_kind)
      EXEC_RESULT_ALU: execute_result = alu_result;
      EXEC_RESULT_PC_PLUS4: execute_result = pc + pc_t'(4);
      EXEC_RESULT_IMM: execute_result = imm;
      EXEC_RESULT_CSR: execute_result = csr_result;
    endcase
  end

endmodule
