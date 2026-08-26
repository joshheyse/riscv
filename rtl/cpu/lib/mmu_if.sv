`timescale 1ns / 1ps

interface mmu_if;
  import riscv_pkg::*;

  mmu_req_t req;
  logic     req_ready;
  mmu_rsp_t rsp;
  logic     rsp_ready;

  modport requester(output req, input req_ready, input rsp, output rsp_ready);
  modport responder(input req, output req_ready, output rsp, input rsp_ready);
endinterface
