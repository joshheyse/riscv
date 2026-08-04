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
  input  logic           halted,
  input  logic           mem_wait,
  input  logic           data_stall,
  input  logic           trap_in_flight,
  input  flow_ctrl_t     flow,
  output pipeline_ctrl_t pipe_ctrl
);

  always_comb begin
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
    end else if (flow.take_trap) begin
      pipe_ctrl.fetch  = STAGE_HOLD;
      pipe_ctrl.if_id  = STAGE_FLUSH;
      pipe_ctrl.id_ex  = STAGE_FLUSH;
      pipe_ctrl.ex_mem = STAGE_FLUSH;
      pipe_ctrl.mem_wb = STAGE_FLUSH;
    end else if (trap_in_flight) begin
      pipe_ctrl.fetch = STAGE_HOLD;
      pipe_ctrl.if_id = STAGE_FLUSH;
    end else if (flow.flush_if_id || flow.flush_id_ex) begin
      pipe_ctrl = '{
          fetch: STAGE_HOLD,
          if_id: STAGE_FLUSH,
          id_ex: STAGE_FLUSH,
          ex_mem: STAGE_ADVANCE,
          mem_wb: STAGE_ADVANCE
      };
    end else if (data_stall) begin
      pipe_ctrl.fetch = STAGE_HOLD;
      pipe_ctrl.if_id = STAGE_HOLD;
      pipe_ctrl.id_ex = STAGE_FLUSH;
    end
  end

  logic _unused_flow_bits;
  assign _unused_flow_bits = |{flow.redirect, flow.take_trap};

endmodule
