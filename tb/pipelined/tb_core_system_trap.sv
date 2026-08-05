// tb_core_system_trap.sv - SYSTEM instruction trap checks for pipelined core.
//
//   make sim DESIGN=pipelined TB=core_system_trap
//   make wave DESIGN=pipelined TB=core_system_trap

`timescale 1ns / 1ps

module tb_core_system_trap
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;

  localparam instr_t ECALL = 32'h0000_0073;
  localparam instr_t EBREAK = 32'h0010_0073;

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

  task automatic issue_first_instr(input instr_t instr, input string what);
    expect_bit(_ibus.req.valid, 1'b1, {what, " fetch request valid"});
    expect_word(_ibus.req.addr, 32'h0000_0000, {what, " fetch request pc"});

    @(posedge _clk);
    #1;

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " fetched valid"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " fetched instr"});

    @(negedge _clk);
    _ibus.rsp = '0;

    @(posedge _clk);
    #1;
  endtask

  task automatic check_system_trap(input instr_t instr, input trap_src_t src, input word_t mcause,
                                   input string what);
    reset_core();
    issue_first_instr(instr, what);

    expect_bit(_dut._if_id.valid, 1'b1, {what, " IF/ID valid"});
    expect_word(_dut._if_id.slot.instr.raw, instr, {what, " IF/ID instr"});
    expect_bit(_dut._ctrl.trap.valid, 1'b1, {what, " decoded trap valid"});
    expect_word(32'(_dut._ctrl.trap.src), 32'(src), {what, " decoded trap src"});
    expect_bit(_dut._id_trap.valid, 1'b1, {what, " trap valid"});
    expect_word(_dut._id_trap.payload.mepc, 32'h0000_0000, {what, " trap mepc"});
    expect_word(_dut._id_trap.payload.mcause, mcause, {what, " trap mcause"});
    expect_word(_dut._id_trap.payload.mtval, 32'h0000_0000, {what, " trap mtval"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_system_trap);
    end

    _rst = 1'b1;
    drive_idle();

    check_system_trap(ECALL, TRAP_SRC_ECALL, 32'h0000_000b, "ecall");
    check_system_trap(EBREAK, TRAP_SRC_EBREAK, 32'h0000_0003, "ebreak");

    if (_errors == 0) begin
      $display("tb_core_system_trap: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_system_trap: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_system_trap: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
