`timescale 1ns / 1ps

module set_associative_cache_synth_top
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  input  mem_req_t upstream_req,
  output logic     upstream_req_ready,
  output mem_rsp_t upstream_rsp,
  input  logic     upstream_rsp_ready,

  output mem_req_t downstream_req,
  input  logic     downstream_req_ready,
  input  mem_rsp_t downstream_rsp,
  output logic     downstream_rsp_ready,

  input  logic              command_valid,
  input  cache_command_op_t command_op,
  output logic              command_ready,
  output logic              command_done_valid,
  input  logic              command_done_ready
);
  mem_if _upstream (
    clk,
    rst
  );
  mem_if _downstream (
    clk,
    rst
  );
  cache_command_if _cache_command ();

  assign _upstream.req = upstream_req;
  assign upstream_req_ready = _upstream.req_ready;
  assign upstream_rsp = _upstream.rsp;
  assign _upstream.rsp_ready = upstream_rsp_ready;

  assign downstream_req = _downstream.req;
  assign _downstream.req_ready = downstream_req_ready;
  assign _downstream.rsp = downstream_rsp;
  assign downstream_rsp_ready = _downstream.rsp_ready;

  assign _cache_command.valid = command_valid;
  assign _cache_command.op = command_op;
  assign command_ready = _cache_command.ready;
  assign command_done_valid = _cache_command.done_valid;
  assign _cache_command.done_ready = command_done_ready;

  set_associative_cache _cache (
    .clk(clk),
    .rst(rst),
    .upstream(_upstream),
    .downstream(_downstream),
    .cache_command(_cache_command)
  );
endmodule
