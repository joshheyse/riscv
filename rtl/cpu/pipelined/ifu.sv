
`timescale 1ns / 1ps

// Pipelined instruction fetch unit.
//
// Contract:
// - `pc` is the next byte address to request.
// - `ibus.req.valid` is a one-cycle request pulse when `fetch_en` is high and
//   the IFU has room for a new outstanding request.
// - The instruction bus may return the response later with `ibus.rsp.ready`.
// - `fetched` is a one-entry output buffer, not a one-cycle pulse. It stays
//   valid while the pipeline is stalled and clears when `fetch_en` says the
//   core can accept it.
//
// The IFU only tracks one outstanding request. On redirect, any older
// outstanding response belongs to the wrong path and must be ignored before
// issuing the redirected fetch.
//
module ifu
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic clk,
  input logic rst,
  input logic fetch_en,
  input logic redirect_en,
  input pc_t  redirect_pc,

  output pc_t    pc,
  output if_id_t fetched,

  ibus_if.master ibus
);

  logic _request_valid;
  pc_t  _request_pc;
  logic _request_issued;
  logic _drop_rsp;

  // Issue at most one fetch at a time. `fetched.valid` does not block issue
  // because a high `fetch_en` also means the core is consuming that entry.
  assign _request_issued = !rst && fetch_en && !_request_valid && !_drop_rsp;
  assign ibus.req.valid  = _request_issued;
  assign ibus.req.addr   = pc;

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
      fetched <= '0;
      _request_valid <= '0;
      _request_pc <= '0;
      _drop_rsp <= 1'b0;
    end else begin
      if (redirect_en) begin
        fetched <= '0;
        pc <= redirect_pc;
        // If a request is already in flight and its response is not arriving
        // this cycle, remember to discard that stale response later.
        _drop_rsp <= _request_valid && !ibus.rsp.ready;
        _request_valid <= 1'b0;
      end else begin
        // A held fetch is consumed when the front of the pipeline advances.
        if (fetch_en && fetched.valid) begin
          fetched <= '0;
        end

        // Drop exactly one wrong-path response after a redirect.
        if (ibus.rsp.ready && _drop_rsp) begin
          _drop_rsp <= 1'b0;
        end

        // Tag each returned instruction with the PC from the request cycle,
        // not the current next-request PC.
        if (ibus.rsp.ready && _request_valid) begin
          fetched <= '{valid: 1'b1, pc: _request_pc, instr: ibus.rsp.instr};
          _request_valid <= 1'b0;
        end

        // Advance `pc` when the request is issued. The response is matched
        // later using `_request_pc`.
        if (_request_issued) begin
          _request_valid <= 1'b1;
          _request_pc <= pc;
          pc <= pc + pc_t'(4);
        end
      end

    end

  end

endmodule
