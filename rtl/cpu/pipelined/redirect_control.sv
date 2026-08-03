`timescale 1ns / 1ps

// Execute-stage control-flow redirect decision.
//
// Branches and jumps resolve in execute. When the current ID/EX slot selects
// anything other than `PC_SRC_INC`, the IFU must discard younger wrong-path work
// and resume fetching from the computed target. JALR-style targets clear bit 0.
//
module redirect_control
  import riscv_pkg::*;
(
  input logic      id_ex_valid,
  input pc_src_t   id_ex_pc_src,
  input logic      id_ex_clear_pc_lsb,
  input alu_data_t alu_result,

  output logic redirect_en,
  output pc_t  redirect_pc
);

  assign redirect_en = id_ex_valid && (id_ex_pc_src != PC_SRC_INC);
  assign redirect_pc = id_ex_clear_pc_lsb ? {alu_result[31:1], 1'b0} : alu_result;

endmodule
