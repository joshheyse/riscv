`timescale 1ns / 1ps

// Global pipeline hold/advance policy.
//
// This block answers the cross-stage question "may the pipe move this cycle?"
// It does not inspect instruction encodings or choose data values. Memory
// waits hold every pipeline register, while data hazards only stop fetch/decode
// and let older stages drain.
//
module pipeline_control
  import riscv_pkg::*;
(
  input logic        halted,
  input logic        ex_mem_valid,
  input logic        ex_mem_mem_write_en,
  input result_src_t ex_mem_result_src,
  input logic        dbus_ready,
  input logic        data_stall,

  output logic mem_instr,
  output logic mem_wait,
  output logic pipe_en,
  output logic fetch_en
);

  assign mem_instr = ex_mem_valid && (ex_mem_mem_write_en || ex_mem_result_src == RESULT_MEM);
  assign mem_wait  = mem_instr && !dbus_ready;
  assign pipe_en   = !mem_wait && !halted;
  assign fetch_en  = pipe_en && !data_stall;

endmodule
