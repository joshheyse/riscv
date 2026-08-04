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
  import pipelined_pkg::*;
(
  input logic              halted,
  input logic              ex_mem_valid,
  input logic              ex_mem_mem_write_en,
  input writeback_result_t ex_mem_writeback_result,
  input logic              dbus_ready,
  input logic              data_stall,

  output logic        mem_instr,
  output logic        mem_wait,
  output stage_ctrl_t fetch_ctrl,
  output stage_ctrl_t if_id_ctrl,
  output stage_ctrl_t id_ex_ctrl,
  output stage_ctrl_t ex_mem_ctrl,
  output stage_ctrl_t mem_wb_ctrl
);

  always_comb begin
    mem_instr = ex_mem_valid && (ex_mem_mem_write_en || ex_mem_writeback_result == WB_RESULT_MEM);
    mem_wait = mem_instr && !dbus_ready;

    fetch_ctrl = STAGE_ADVANCE;
    if_id_ctrl = STAGE_ADVANCE;
    id_ex_ctrl = STAGE_ADVANCE;
    ex_mem_ctrl = STAGE_ADVANCE;
    mem_wb_ctrl = STAGE_ADVANCE;

    if (halted) begin
      fetch_ctrl  = STAGE_HOLD;
      if_id_ctrl  = STAGE_HOLD;
      id_ex_ctrl  = STAGE_HOLD;
      ex_mem_ctrl = STAGE_HOLD;
      mem_wb_ctrl = STAGE_HOLD;
    end else if (mem_wait) begin
      fetch_ctrl  = STAGE_HOLD;
      if_id_ctrl  = STAGE_HOLD;
      id_ex_ctrl  = STAGE_HOLD;
      ex_mem_ctrl = STAGE_HOLD;
      mem_wb_ctrl = STAGE_HOLD;
    end else if (data_stall) begin
      fetch_ctrl = STAGE_HOLD;
      if_id_ctrl = STAGE_HOLD;
      id_ex_ctrl = STAGE_FLUSH;
    end
  end

endmodule
