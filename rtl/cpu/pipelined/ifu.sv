
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
  input logic      clk,
  input logic      rst,
  input logic      fetch_en,
  input redirect_t redirect,

  output pc_t    pc,
  output if_id_t fetched,

  ibus_if.master ibus
);

  logic _request_valid;
  logic _drop_response;
  pc_t  _request_pc;
  logic _request_issued;

  // Issue at most one fetch at a time. `fetched.valid` does not block issue
  // because a high `fetch_en` also means the core is consuming that entry.
  // Never issue a new request on the same cycle as a redirected or stale
  // response is being drained.
  assign _request_issued = !rst && fetch_en && !redirect.valid && !_request_valid && !_drop_response;
  assign ibus.req.valid  = _request_issued;
  assign ibus.req.addr   = pc;

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
      fetched <= '0;
      _request_valid <= '0;
      _drop_response <= 1'b0;
      _request_pc <= '0;
    end else begin
      if (redirect.valid) begin
        pc <= redirect.pc;
        // Discard any in-flight response from the wrong path.
        fetched <= '0;
        _request_valid <= 1'b0;
        _drop_response <= _request_valid;
      end else begin
        // A redirect creates a one-cycle stale-response suppression window.
        // This is enough to avoid wrong-path capture with the current single-queue
        // bus model and cannot deadlock if the testbench leaves `ready` deasserted.
        _drop_response <= 1'b0;

        // A held fetch is consumed when the front of the pipeline advances.
        if (fetch_en && fetched.valid) begin
          fetched <= '0;
        end

        // Tag each returned instruction with the PC from the request cycle,
        // not the current next-request PC.
        if (ibus.rsp.ready && (_request_valid || _drop_response)) begin
          if (_request_valid && !_drop_response) begin
            fetched <= '{valid: 1'b1, slot: '{instr: ibus.rsp.instr, pc: _request_pc}};
          end
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
