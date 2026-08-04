`timescale 1ns / 1ps

module mem_stage
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input ex_mem_t ex_mem,

  output logic    mem_wait,
  output mem_wb_t mem_wb_payload,

  dbus_if.master dbus
);

  mem_data_t _mem_read_data;
  reg_data_t _mem_result_data;
  logic      _mem_access;

  assign _mem_access = ex_mem.valid && !ex_mem.trap.valid && (ex_mem.ctrl.mem_write_en || ex_mem.ctrl.writeback_result == WB_RESULT_MEM);
  assign mem_wait = _mem_access && !dbus.rsp.ready;
  assign dbus.req.valid = _mem_access;
  assign dbus.req.write_en = _mem_access && ex_mem.ctrl.mem_write_en;

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
          trap: ex_mem.trap
      };

  pc_t _unused_pc;
  assign _unused_pc = ex_mem.pc;

endmodule
