`timescale 1ns / 1ps

module mem_stage
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic clk,
  input logic rst,

  /* verilator lint_off UNUSEDSIGNAL */
  input ex_mem_t     ex_mem,
  /* verilator lint_on UNUSEDSIGNAL */
  input csr_status_t csr_status,

  output logic    mem_wait,
  output mem_wb_t mem_wb_payload,

  mem_if.master dbus
);


  // This master has somewhere to put every response it asked for, so it takes
  // them unconditionally. Drive it for real if that ever stops being true.
  assign dbus.rsp_ready = 1'b1;

  mem_data_t   _mem_read_data;
  reg_data_t   _mem_result_data;
  logic        _mem_instr;
  logic        _mem_access;
  trap_req_t   _mem_trap_req;
  trap_stage_t _mem_trap;
  trap_stage_t _trap;

  // The access is presented until the bus accepts it, then held off the bus
  // while its response is outstanding. `ex_mem` is stable across both, because
  // `mem_wait` stalls the pipeline for the whole transaction.
  logic        _accepted;
  logic        _accept;
  logic        _response_here;

  assign _mem_instr = ex_mem.valid && !ex_mem.trap.valid && (ex_mem.ctrl.mem_write_en || ex_mem.ctrl.writeback_result == WB_RESULT_MEM);
  assign _mem_access = _mem_instr && !_mem_trap_req.valid;
  assign _accept = dbus.req.valid && dbus.req_ready;
  assign _response_here = dbus.rsp.valid && (_accepted || _accept);
  assign mem_wait = _mem_access && !_response_here;
  assign dbus.req.valid = _mem_access && !_accepted;

  always_ff @(posedge clk) begin
    if (rst) begin
      _accepted <= 1'b0;
    end else if (_response_here) begin
      _accepted <= 1'b0;
    end else if (_accept) begin
      _accepted <= 1'b1;
    end
  end
  assign dbus.req.write_en = _mem_access && ex_mem.ctrl.mem_write_en;
  assign dbus.req.addr = ex_mem.alu_result;
  assign _trap = ex_mem.trap.valid ? ex_mem.trap : _mem_trap;

  mem_trap_control _mem_trap_control (
    .valid(_mem_instr),
    .addr(ex_mem.alu_result),
    .mem_size(ex_mem.ctrl.mem_size),
    .mem_write_en(ex_mem.ctrl.mem_write_en),
    .trap(_mem_trap_req)
  );

  trap_control _trap_control (
    .trap_req(_mem_trap_req),
    .pc(ex_mem.pc),
    .csr_status(csr_status),
    .trap(_mem_trap)
  );

  lsu _lsu (
    .addr(ex_mem.alu_result),
    .write_data(ex_mem.write_data),
    .mem_size(ex_mem.ctrl.mem_size),
    .mem_unsigned(ex_mem.ctrl.mem_unsigned),
    .read_data(_mem_read_data),
    .mem_write_data(dbus.req.write_data),
    .mem_read_data(dbus.rsp.read_data),
    .write_mask(dbus.req.write_mask)
  );

  writeback_mux _mem_result_mux (
    .writeback_result(ex_mem.ctrl.writeback_result),
    .execute_result(ex_mem.execute_result),
    .read_data(_mem_read_data),
    .writeback_data(_mem_result_data)
  );

  assign mem_wb_payload = '{
          valid: ex_mem.valid,
          ctrl: ex_mem.ctrl,
          result: _mem_result_data,
          rd: ex_mem.rd,
          trap: _trap
      };

endmodule
