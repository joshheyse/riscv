`timescale 1ns / 1ps

// Execute-stage control-flow redirect decision.
//
// Branches and jumps resolve in execute. When the current ID/EX slot selects
// anything other than `PC_SRC_INC`, the IFU must discard younger wrong-path work
// and resume fetching from the computed target. JALR-style targets clear bit 0.
//
module redirect_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic      id_ex_valid,
  input pc_src_t   id_ex_pc_src,
  input logic      id_ex_clear_pc_lsb,
  input alu_data_t alu_result,

  output redirect_t redirect,
  output trap_req_t trap
);

  pc_t  _target_pc;
  logic _redirect_valid;
  logic _target_misaligned;

  assign _target_pc = id_ex_clear_pc_lsb ? {alu_result[31:1], 1'b0} : alu_result;
  assign _redirect_valid = id_ex_valid && (id_ex_pc_src != PC_SRC_INC);
  assign _target_misaligned = _redirect_valid && (_target_pc[1:0] != 2'b00);

  assign redirect.valid = _redirect_valid && !_target_misaligned;
  assign redirect.pc = _target_pc;
  assign trap = '{
          valid: _target_misaligned,
          src: TRAP_SRC_INSTR_ADDR_MISALIGNED,
          tval: _target_pc
      };

endmodule
