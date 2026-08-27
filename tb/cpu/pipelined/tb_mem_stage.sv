// tb_mem_stage.sv - memory-stage side-effect suppression checks.
//
//   make sim DESIGN=pipelined TB=mem_stage
//   make wave DESIGN=pipelined TB=mem_stage

`timescale 1ns / 1ps

module tb_mem_stage
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;

  logic        _clk;
  logic        _rst;
  ex_mem_t     _ex_mem;
  csr_status_t _csr_status;
  logic        _mem_wait;
  mem_wb_t     _mem_wb_payload;

  vmem_if _dbus (
    _clk,
    _rst
  );

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  mem_stage _dut (
    .clk(_clk),
    .rst(_rst),
    .ex_mem(_ex_mem),
    .csr_status(_csr_status),
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
    _csr_status = '0;
    _csr_status.mtvec = '{base: 30'h0000_0080, mode: TVEC_MODE_DIRECT};
    _csr_status.priv_mode = PRIV_MACHINE;
    _dbus.rsp = '0;
    _dbus.rsp.valid = 1'b1;
    // The combinational checks below run against a bus that never accepts, so
    // the stage stays in its request-presented state throughout.
    _dbus.req_ready = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mem_stage);
    end

    _rst = 1'b1;
    clear_inputs();
    @(posedge _clk);
    #1;
    _rst = 1'b0;

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
    _dbus.rsp.valid = 1'b0;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "trapped load does not request dbus");
    expect_bit(_dbus.req.write_en, 1'b0, "trapped load does not assert write");
    expect_bit(_mem_wait, 1'b0, "trapped load does not wait");
    expect_bit((|_mem_wb_payload.ctrl) === 1'b1, 1'b1, "payload ctrl is observable");
    expect_bit((|_mem_wb_payload.rd) === 1'b0, 1'b1, "payload rd is observable");
    expect_bit((|_mem_wb_payload.trap.payload) === 1'b0, 1'b1, "payload trap data is observable");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_0040;
    _ex_mem.ctrl.writeback_result = WB_RESULT_MEM;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h1000_0002;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "misaligned load does not request dbus");
    expect_bit(_mem_wait, 1'b0, "misaligned load does not wait");
    expect_bit(_mem_wb_payload.trap.valid, 1'b1, "misaligned load produces trap");
    expect_word(_mem_wb_payload.trap.payload.epc, 32'h0000_0040, "misaligned load epc");
    expect_word(_mem_wb_payload.trap.payload.cause, 32'h0000_0004, "misaligned load cause");
    expect_word(_mem_wb_payload.trap.payload.tval, 32'h1000_0002, "misaligned load tval");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_0044;
    _ex_mem.ctrl.mem_write_en = 1'b1;
    _ex_mem.ctrl.mem_size = MEM_SIZE_HALF;
    _ex_mem.alu_result = 32'h1000_0001;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "misaligned store does not request dbus");
    expect_bit(_mem_wb_payload.trap.valid, 1'b1, "misaligned store produces trap");
    expect_word(_mem_wb_payload.trap.payload.epc, 32'h0000_0044, "misaligned store epc");
    expect_word(_mem_wb_payload.trap.payload.cause, 32'h0000_0006, "misaligned store cause");
    expect_word(_mem_wb_payload.trap.payload.tval, 32'h1000_0001, "misaligned store tval");

    // A load is presented until the bus accepts it, then held off the bus
    // until the response arrives -- leaving it asserted would re-offer a
    // transaction the slave has already taken.
    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.ctrl.writeback_result = WB_RESULT_MEM;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h1000_0100;
    _dbus.rsp.valid = 1'b0;
    #1;
    expect_bit(_dbus.req.valid, 1'b1, "load is presented");
    expect_bit(_mem_wait, 1'b1, "load waits while unaccepted");

    _dbus.req_ready = 1'b1;
    #1;
    expect_bit(_mem_wait, 1'b1, "acceptance alone does not end the wait");
    @(posedge _clk);
    #1;
    _dbus.req_ready = 1'b0;
    #1;
    expect_bit(_dbus.req.valid, 1'b0, "accepted load leaves the bus");
    expect_bit(_mem_wait, 1'b1, "load still waits for its response");

    _dbus.rsp.valid = 1'b1;
    _dbus.rsp.read_data = 32'h1234_5678;
    #1;
    expect_bit(_mem_wait, 1'b0, "response ends the wait");
    expect_word(_mem_wb_payload.result, 32'h1234_5678, "load result reaches writeback");
    @(posedge _clk);
    #1;

    // MMU failures complete the request but replace its normal result with a
    // precisely attributed load/store trap carrying the virtual address.
    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_0080;
    _ex_mem.ctrl.writeback_result = WB_RESULT_MEM;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h8123_4000;
    _dbus.req_ready = 1'b1;
    _dbus.rsp.fault = MMU_FAULT_PAGE;
    #1;
    expect_bit(_mem_wait, 1'b0, "load page fault completes memory wait");
    expect_bit(_mem_wb_payload.trap.valid, 1'b1, "load page fault produces trap");
    expect_word(_mem_wb_payload.trap.payload.cause, 32'd13, "load page fault cause");
    expect_word(_mem_wb_payload.trap.payload.tval, 32'h8123_4000,
                "load page fault virtual address");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_0084;
    _ex_mem.ctrl.mem_write_en = 1'b1;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'h9234_5000;
    _dbus.req_ready = 1'b1;
    _dbus.rsp.fault = MMU_FAULT_PAGE;
    #1;
    expect_bit(_mem_wb_payload.trap.valid, 1'b1, "store page fault produces trap");
    expect_word(_mem_wb_payload.trap.payload.cause, 32'd15, "store page fault cause");
    expect_word(_mem_wb_payload.trap.payload.tval, 32'h9234_5000,
                "store page fault virtual address");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_0088;
    _ex_mem.ctrl.writeback_result = WB_RESULT_MEM;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'ha345_6000;
    _dbus.req_ready = 1'b1;
    _dbus.rsp.fault = MMU_FAULT_ACCESS;
    #1;
    expect_word(_mem_wb_payload.trap.payload.cause, 32'd5, "load access fault cause");

    clear_inputs();
    _ex_mem.valid = 1'b1;
    _ex_mem.pc = 32'h0000_008c;
    _ex_mem.ctrl.mem_write_en = 1'b1;
    _ex_mem.ctrl.mem_size = MEM_SIZE_WORD;
    _ex_mem.alu_result = 32'hb456_7000;
    _dbus.req_ready = 1'b1;
    _dbus.rsp.fault = MMU_FAULT_ACCESS;
    #1;
    expect_word(_mem_wb_payload.trap.payload.cause, 32'd7, "store access fault cause");

    if (_errors == 0) begin
      $display("tb_mem_stage: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_mem_stage: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

endmodule
