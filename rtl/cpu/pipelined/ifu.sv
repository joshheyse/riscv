
`timescale 1ns / 1ps

// Pipelined instruction fetch unit.
//
// Contract:
// - `pc` is the next byte address to request.
// - Once issued, `ibus.req.valid` and `ibus.req.addr` remain stable until the
//   instruction-side memory port returns `ibus.rsp.valid`.
// - The instruction-side memory port may return the response later with
//   `ibus.rsp.valid`.
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

  mem_if.master ibus
);


  // This master has somewhere to put every response it asked for, so it takes
  // them unconditionally. Drive it for real if that ever stops being true.
  assign ibus.rsp_ready = 1'b1;

  // A fetch is in flight from the cycle it is presented until its response
  // arrives, but the request itself comes off the bus as soon as the slave
  // accepts it -- holding it any longer would be offering a transaction that
  // has already been taken.
  logic _request_valid;  // presented, not yet accepted
  logic _awaiting_rsp;  // accepted, response outstanding
  logic _drop_response;
  pc_t  _request_pc;
  logic _request_issued;
  logic _request_accepted;
  logic _in_flight;
  logic _response_here;

  assign _request_accepted = _request_valid && ibus.req_ready;
  assign _in_flight = _request_valid || _awaiting_rsp;
  assign _response_here = ibus.rsp.valid && (_awaiting_rsp || _request_accepted);

  // Issue at most one fetch at a time. `fetched.valid` does not block issue
  // because a high `fetch_en` also means the core is consuming that entry.
  // Never issue a new request on the same cycle as a redirected or stale
  // response is being drained.
  //
  // Issuing must also wait for the cycle *after* a response, not the same one.
  // `fetched` is a single entry: the next request is only allowed once
  // `fetch_en` has been seen high with that entry present, which is what
  // guarantees the core consumed it. Issuing a cycle earlier lets the following
  // response overwrite an unconsumed entry and silently drop an instruction.
  assign _request_issued = !rst && fetch_en && !redirect.valid && !_drop_response && !_in_flight;
  assign ibus.req.valid = _request_valid;
  assign ibus.req.write_en = 1'b0;
  assign ibus.req.addr = _request_pc;
  assign ibus.req.write_data = '0;
  assign ibus.req.write_mask = '0;

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= '0;
      fetched <= '0;
      _request_valid <= '0;
      _awaiting_rsp <= 1'b0;
      _drop_response <= 1'b0;
      _request_pc <= '0;
    end else begin
      if (redirect.valid) begin
        pc <= redirect.pc;
        // Keep an in-flight request asserted until it completes, but discard
        // its wrong-path response before issuing the redirected fetch.
        fetched <= '0;
        // A response may arrive in the same cycle as the redirect. Consume it
        // here so the completed request is not presented to the arbiter again.
        if (_response_here) begin
          _request_valid <= 1'b0;
          _awaiting_rsp  <= 1'b0;
          _drop_response <= 1'b0;
        end else if (_in_flight) begin
          _drop_response <= 1'b1;
          if (_request_accepted) begin
            _request_valid <= 1'b0;
            _awaiting_rsp  <= 1'b1;
          end
        end
      end else begin
        // A held fetch is consumed when the front of the pipeline advances.
        if (fetch_en && fetched.valid) begin
          fetched <= '0;
        end

        // Tag each returned instruction with the PC from the request cycle,
        // not the current next-request PC.
        if (_response_here) begin
          if (!_drop_response) begin
            fetched <= '{valid: 1'b1, slot: '{instr: ibus.rsp.read_data, pc: _request_pc}};
          end
          _request_valid <= 1'b0;
          _awaiting_rsp  <= 1'b0;
          _drop_response <= 1'b0;
        end else if (_request_accepted) begin
          _request_valid <= 1'b0;
          _awaiting_rsp  <= 1'b1;
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
