// tb_mem_stage.sv - memory-stage side-effect suppression checks.
//
//   make sim DESIGN=pipelined TB=mem_stage
//   make wave DESIGN=pipelined TB=mem_stage

`timescale 1ns / 1ps

module tb_mem_stage
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  ex_mem_t _ex_mem;
  logic    _mem_wait;
  mem_wb_t _mem_wb_payload;

  dbus_if _dbus ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  mem_stage _dut (
    .ex_mem(_ex_mem),
    .mem_wait(_mem_wait),
    .mem_wb_payload(_mem_wb_payload),
    .dbus(_dbus)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic clear_inputs();
    _ex_mem = '0;
    _dbus.rsp = '0;
    _dbus.rsp.ready = 1'b1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mem_stage);
    end

    clear_inputs();
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "bubble does not request dbus");
    expect_bit(_mem_wait, 1'b0, "bubble does not wait");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.ctrl.mem_write_en = 1'b1;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h1000_0040;
    _ex_mem.write_data = 32'hcafe_babe;
    #1;
    expect_bit(_dbus.req.valid, 1'b1, "store requests dbus");
    expect_bit(_dbus.req.write_en, 1'b1, "store asserts dbus write");
    expect_word(_dbus.req.addr, 32'h1000_0040, "store address");
    expect_word(_dbus.req.write_data, 32'hcafe_babe, "store write data");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.trap.valid = 1'b1;
    _ex_mem.ctrl.mem_write_en = 1'b1;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h1000_0080;
    _ex_mem.write_data = 32'h1234_5678;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "trapped store does not request dbus");
    expect_bit(_dbus.req.write_en, 1'b0, "trapped store does not assert write");
    expect_bit(_mem_wait, 1'b0, "trapped store does not wait");
    expect_bit(_mem_wb_payload.valid, 1'b1, "trapped store still drains to MEM/WB");
    expect_bit(_mem_wb_payload.trap.valid, 1'b1, "trapped store payload carries trap");
    expect_word(_mem_wb_payload.result, 32'h0000_0000, "trapped store writeback payload is unused");
    expect_bit(_mem_wb_payload.ctrl.mem_write_en, 1'b1, "trapped store keeps original control");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.trap.valid = 1'b1;
    _ex_mem.ctrl.writeback_result = WB_RESULT_MEM;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h1000_00c0;
    _dbus.rsp.ready = 1'b0;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "trapped load does not request dbus");
    expect_bit(_dbus.req.write_en, 1'b0, "trapped load does not assert write");
    expect_bit(_mem_wait, 1'b0, "trapped load does not wait");
    expect_bit((|_mem_wb_payload.ctrl) === 1'b1, 1'b1, "payload ctrl is observable");
    expect_bit((|_mem_wb_payload.rd) === 1'b0, 1'b1, "payload rd is observable");
    expect_bit((|_mem_wb_payload.trap.payload) === 1'b0, 1'b1, "payload trap data is observable");

    if (_errors == 0) begin
      $display("tb_mem_stage: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_mem_stage: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

endmodule
