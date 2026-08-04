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

  output logic           mem_instr,
  output logic           mem_wait,
  output pipeline_ctrl_t pipe_ctrl
);

  always_comb begin
    mem_instr = ex_mem_valid && (ex_mem_mem_write_en || ex_mem_writeback_result == WB_RESULT_MEM);
    mem_wait = mem_instr && !dbus_ready;

    pipe_ctrl = '{
        fetch: STAGE_ADVANCE,
        if_id: STAGE_ADVANCE,
        id_ex: STAGE_ADVANCE,
        ex_mem: STAGE_ADVANCE,
        mem_wb: STAGE_ADVANCE
    };

    if (halted) begin
      pipe_ctrl = '{
          fetch: STAGE_HOLD,
          if_id: STAGE_HOLD,
          id_ex: STAGE_HOLD,
          ex_mem: STAGE_HOLD,
          mem_wb: STAGE_HOLD
      };
    end else if (mem_wait) begin
      pipe_ctrl = '{
          fetch: STAGE_HOLD,
          if_id: STAGE_HOLD,
          id_ex: STAGE_HOLD,
          ex_mem: STAGE_HOLD,
          mem_wb: STAGE_HOLD
      };
    end else if (data_stall) begin
      pipe_ctrl.fetch = STAGE_HOLD;
      pipe_ctrl.if_id = STAGE_HOLD;
      pipe_ctrl.id_ex = STAGE_FLUSH;
    end
  end

endmodule
