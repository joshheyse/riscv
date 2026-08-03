`timescale 1ns / 1ps

// Selects the pre-memory result produced by the execute stage.
//
// Loads still pass through this path with ALU_RES_ALU: the ALU result is the
// load address. The final writeback mux later replaces it with memory read data.
module execute_result_mux
  import riscv_pkg::*;
(
  input alu_result_src_t alu_result_src,
  input pc_t             pc,
  input imm_t            imm,
  input alu_data_t       alu_result,

  output reg_data_t execute_result
);

  always_comb begin
    unique case (alu_result_src)
      ALU_RES_ALU: execute_result = alu_result;
      ALU_RES_PC_PLUS4: execute_result = pc + pc_t'(4);
      ALU_RES_IMM: execute_result = imm;
    endcase
  end

endmodule
