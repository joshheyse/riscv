// tb_core_trap_precision.sv - precise-trap ordering checks.
//
//   make sim DESIGN=pipelined TB=core_trap_precision
//   make wave DESIGN=pipelined TB=core_trap_precision

`timescale 1ns / 1ps

module tb_core_trap_precision
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 300;

  localparam instr_t ADDI_X1_X0_7 = 32'h0070_0093;
  localparam instr_t ILLEGAL = 32'h0000_0000;
  localparam instr_t ADDI_X2_X0_9 = 32'h0090_0113;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .ibus(_ibus),
    .dbus(_dbus)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

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

  task automatic drive_idle();
    _ibus.rsp = '0;
    _dbus.rsp = '0;
    _dbus.rsp.ready = 1'b1;
  endtask

  task automatic reset_core();
    @(negedge _clk);
    _rst = 1'b1;
    drive_idle();
    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;
  endtask

  task automatic wait_fetch_req(input pc_t exp_addr, input string what);
    int unsigned waits;
    waits = 0;

    #1;
    while (!_ibus.req.valid && waits < 20) begin
      waits++;
      @(negedge _clk);
      #1;
    end

    expect_bit(_ibus.req.valid, 1'b1, {what, " request valid"});
    expect_word(_ibus.req.addr, exp_addr, {what, " request addr"});
  endtask

  task automatic fetch_instr(input pc_t exp_addr, input instr_t instr, input string what);
    wait_fetch_req(exp_addr, what);

    @(posedge _clk);
    #1;
    expect_word(_pc, exp_addr + pc_t'(4), {what, " request advances pc"});

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " response captured"});
    expect_word(_dut._fetched.pc, exp_addr, {what, " response pc"});
    expect_word(_dut._fetched.instr.raw, instr, {what, " response instr"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic offer_squashed_instr(input pc_t exp_addr, input instr_t instr, input string what);
    wait_fetch_req(exp_addr, what);

    @(posedge _clk);
    #1;

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " speculative response may enter IFU output"});
    expect_word(_dut._fetched.instr.raw, instr, {what, " speculative response is visible before trap redirect"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic drain_until_trap_entry();
    int unsigned waits;
    waits = 0;

    #1;
    while ((_dut._csr_file._mcause != 32'h0000_0002) && waits < 20) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(_halted, 1'b0, "trap entry does not halt");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "trap eventually writes mcause");
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_trap_precision);
    end

    _rst = 1'b1;
    drive_idle();
    reset_core();

    _dut._reg_file._regs[1] = '0;
    _dut._reg_file._regs[2] = '0;

    fetch_instr(32'h0000_0000, ADDI_X1_X0_7, "older addi");
    fetch_instr(32'h0000_0004, ILLEGAL, "illegal instruction");
    offer_squashed_instr(32'h0000_0008, ADDI_X2_X0_9, "younger addi");

    drain_until_trap_entry();

    expect_word(_dut._reg_file._regs[1], 32'h0000_0007, "older instruction commits before trap");
    expect_word(_dut._reg_file._regs[2], 32'h0000_0000, "younger instruction is squashed");
    expect_word(_dut._csr_file._mepc, 32'h0000_0004, "mepc points at trapped instruction");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "mcause records illegal instruction");
    expect_word(_dut._csr_file._mtval, ILLEGAL, "mtval records trapped instruction bits");

    if (_errors == 0) begin
      $display("tb_core_trap_precision: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_trap_precision: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_trap_precision: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
