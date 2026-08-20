`timescale 1ns / 1ps

interface mem_if
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst
);

  // Two channels, four handshake signals.
  //
  //   req / req_ready  -- master asks, slave accepts. A request transfers on the
  //                       edge where both are high; that is the only moment a
  //                       slave may sample the payload. A master holds `req` and
  //                       every payload field stable until the transfer happens,
  //                       and must never wait for `req_ready` before asserting
  //                       `req.valid` -- that rule is what keeps `req_ready`
  //                       free to depend combinationally on `req.valid`, as
  //                       `mem_arbiter` needs in order to grant.
  //
  //   rsp / rsp_ready  -- slave answers, master takes it. A response transfers
  //                       on the edge where both are high, no earlier than the
  //                       request transfer. The slave holds `rsp.valid` and
  //                       `read_data` stable until that happens, and must never
  //                       wait for `rsp_ready` before asserting `rsp.valid` --
  //                       the mirror of the request-channel rules.
  //
  // One transaction in flight at a time, on both channels.
  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  mem_req_t req;
  logic     req_ready;
  mem_rsp_t rsp;
  logic     rsp_ready;
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  modport master(output req, input req_ready, input rsp, output rsp_ready);
  modport slave(input req, output req_ready, output rsp, input rsp_ready);

  // One transaction in flight, tracked here so every bus segment is checked
  // without a line of assertion code in any module.
  logic _outstanding;
  logic _req_transfer;
  logic _rsp_transfer;

  assign _req_transfer = req.valid && req_ready;
  assign _rsp_transfer = rsp.valid && rsp_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      _outstanding <= 1'b0;
    end else if (_req_transfer && !_rsp_transfer) begin
      _outstanding <= 1'b1;
    end else if (_rsp_transfer) begin
      _outstanding <= 1'b0;
    end
  end

  // R2. The rule both L1 cache deadlocks broke before this signal existed.
  a_req_stable :
  assert property (@(posedge clk) disable iff (rst)
      (req.valid && !req_ready) |=> (req.valid && $stable(
      req
  )))
  else $error("mem_if: request withdrawn or mutated before it was accepted");

  // P2. The mirror of R2: a response may not be withdrawn or mutated before the
  // master takes it.
  a_rsp_stable :
  assert property (@(posedge clk) disable iff (rst)
      (rsp.valid && !rsp_ready) |=> (rsp.valid && $stable(
      rsp
  )))
  else $error("mem_if: response withdrawn or mutated before it was accepted");

  // P1. No response that nobody asked for.
  a_rsp_follows_accept :
  assert property (@(posedge clk) disable iff (rst) rsp.valid |-> (_outstanding || _req_transfer))
  else $error("mem_if: response with no accepted request");

  // R4. Single outstanding.
  a_single_outstanding :
  assert property (@(posedge clk) disable iff (rst)
      _req_transfer |-> (!_outstanding || _rsp_transfer))
  else $error("mem_if: second request accepted while one is outstanding");

endinterface
