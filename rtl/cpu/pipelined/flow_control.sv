`timescale 1ns / 1ps

module flow_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input redirect_t redirect,
  input trap_t trap,
  output flow_ctrl_t flow
);

  always_comb begin
    flow = '0;
    if (trap.valid) begin
      flow.redirect.valid = 1'b1;
      flow.redirect.pc    = trap.pc;
      flow.take_trap      = 1'b1;
      flow.flush_if_id    = 1'b1;
      flow.flush_id_ex    = 1'b1;
    end else if (redirect.valid) begin
      flow.redirect    = redirect;
      flow.take_trap   = 1'b0;
      flow.flush_if_id = 1'b1;
      flow.flush_id_ex = 1'b1;
    end
  end

  logic _unused_trap_payload;
  assign _unused_trap_payload = |{trap.mepc, trap.mcause, trap.mtval};

endmodule
