`timescale 1ns / 1ps

module flow_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input  redirect_t   redirect,
  /* verilator lint_off UNUSEDSIGNAL */
  input  trap_stage_t trap,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        mret_valid,
  input  logic        sret_valid,
  input  mepc_t       mepc,
  input  sepc_t       sepc,
  output flow_ctrl_t  flow

);

  always_comb begin
    flow = '0;
    if (trap.valid) begin
      flow.action         = FLOW_ACTION_TRAP;
      flow.redirect.valid = 1'b1;
      flow.redirect.pc    = trap.payload.pc;
    end else if (mret_valid) begin
      flow.action         = FLOW_ACTION_MRET;
      flow.redirect.valid = 1'b1;
      flow.redirect.pc    = mepc;
    end else if (sret_valid) begin
      flow.action         = FLOW_ACTION_SRET;
      flow.redirect.valid = 1'b1;
      flow.redirect.pc    = sepc;
    end else if (redirect.valid) begin
      flow.action   = FLOW_ACTION_REDIRECT;
      flow.redirect = redirect;
    end
  end

endmodule
