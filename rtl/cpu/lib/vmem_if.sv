`timescale 1ns / 1ps

interface vmem_if
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst
);

  // Virtual-memory request/response channel used by instruction fetch and the
  // load/store path before address translation. `req.addr` is a virtual byte
  // address. A translation adapter either forwards the operation on a physical
  // `mem_if` after successful translation or returns an MMU fault without
  // issuing a physical-memory request.
  //
  // Two channels, four handshake signals.
  //
  //   req / req_ready  -- master asks, slave accepts. A request transfers on the
  //                       edge where both are high; that is the only moment a
  //                       slave may sample the payload. A master holds `req` and
  //                       every payload field stable until the transfer happens,
  //                       and must never wait for `req_ready` before asserting
  //                       `req.valid`.
  //
  //   rsp / rsp_ready  -- slave answers, master takes it. A response transfers
  //                       on the edge where both are high, no earlier than the
  //                       request transfer. The slave holds `rsp.valid` and
  //                       its data/fault payload stable until that happens, and
  //                       must never wait for `rsp_ready` before asserting
  //                       `rsp.valid` -- the mirror of the request-channel
  //                       rules.
  //
  // One transaction may be outstanding at a time. A response with
  // `fault != MMU_FAULT_NONE` completes the virtual request without valid read
  // data; the requester interprets the fault according to its access type.
  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  vmem_req_t req;
  logic      req_ready;
  vmem_rsp_t rsp;
  logic      rsp_ready;
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  modport master(output req, input req_ready, input rsp, output rsp_ready);
  modport slave(input req, output req_ready, output rsp, input rsp_ready);

  // Track the one permitted outstanding transaction so every virtual-memory
  // segment gets the same protocol checks without module-local assertions.
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

  // A requester cannot withdraw or modify a request before it is accepted.
  a_req_stable :
  assert property (@(posedge clk) disable iff (rst)
      (req.valid && !req_ready) |=> (req.valid && $stable(
      req
  )))
  else $error("vmem_if: request withdrawn or mutated before it was accepted");

  // A responder cannot withdraw or modify a response before it is accepted.
  a_rsp_stable :
  assert property (@(posedge clk) disable iff (rst)
      (rsp.valid && !rsp_ready) |=> (rsp.valid && $stable(
      rsp
  )))
  else $error("vmem_if: response withdrawn or mutated before it was accepted");

  // Every response must correspond to an accepted request.
  a_rsp_follows_accept :
  assert property (@(posedge clk) disable iff (rst) rsp.valid |-> (_outstanding || _req_transfer))
  else $error("vmem_if: response with no accepted request");

  // A second request cannot be accepted before the prior response transfers.
  a_single_outstanding :
  assert property (@(posedge clk) disable iff (rst)
      _req_transfer |-> (!_outstanding || _rsp_transfer))
  else $error("vmem_if: second request accepted while one is outstanding");

endinterface
