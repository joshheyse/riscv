// tb_core.sv - handshaked smoke test for the pipelined core.
//
//   make sim DESIGN=pipelined TB=core
//   make wave DESIGN=pipelined TB=core
//
// The pipelined IFU issues one-cycle request pulses and accepts responses on a
// later clock. This testbench drives that contract directly instead of assuming
// an instruction can be supplied every cycle.

`timescale 1ns / 1ps

module tb_core
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 300;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  core _dut (
    .clk   (_clk),
    .rst   (_rst),
    .halted(_halted),
    .pc    (_pc),
    .ibus  (_ibus),
    .dbus  (_dbus)
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

  task automatic expect_regaddr(input regaddr_t got, input regaddr_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got x%0d, expected x%0d", $time, what, got, exp);
    end
  endtask

  task automatic drive_idle();
    _ibus.rsp = '0;
    _dbus.rsp = '0;
  endtask

  task automatic reset_core(input string what);
    @(negedge _clk);
    _rst = 1'b1;
    drive_idle();
    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, {what, " reset does not halt"});
    expect_word(_pc, 32'h0000_0000, {what, " reset pc"});

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

  task automatic drain(input int unsigned cycles);
    repeat (cycles) begin
      @(posedge _clk);
      #1;
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core);
    end

    _rst = 1'b1;
    drive_idle();
    reset_core("alu");

    _dbus.rsp.ready = 1'b1;
    _dut._reg_file._regs[2] = 32'h1111_2222;
    _dut._reg_file._regs[3] = 32'h3333_4444;

    fetch_instr(32'h0000_0000, 32'h0050_0093, "addi x1,x0,5");
    fetch_instr(32'h0000_0004, 32'h0031_8233, "add x4,x3,x3");

    drain(6);
    expect_word(_dut._reg_file._regs[1], 32'h0000_0005, "WB writes addi result");
    expect_word(_dut._reg_file._regs[4], 32'h6666_8888, "WB writes add result");
    expect_bit(_halted, 1'b0, "legal ALU sequence does not halt");

    reset_core("load");

    _dut._reg_file._regs[2] = 32'h1000_0000;
    _dbus.rsp.ready = 1'b0;
    _dbus.rsp.read_data = 32'h0000_0000;

    fetch_instr(32'h0000_0000, 32'h0001_2303, "lw x6,0(x2)");
    drain(3);

    expect_bit(_dbus.req.valid, 1'b1, "load requests data bus");
    expect_bit(_dbus.req.write_en, 1'b0, "load request is read");
    expect_word(_dbus.req.addr, 32'h1000_0000, "load request address");
    expect_bit(_dut._fetch_ctrl == STAGE_HOLD, 1'b1, "load holds fetch while dbus not ready");
    expect_bit(_ibus.req.valid, 1'b0, "load wait suppresses fetch");

    @(posedge _clk);
    #1;
    expect_bit(_dbus.req.valid, 1'b1, "load keeps request valid while stalled");
    expect_word(_dbus.req.addr, 32'h1000_0000, "load keeps address stable while stalled");

    @(negedge _clk);
    _dbus.rsp.ready = 1'b1;
    _dbus.rsp.read_data = 32'ha5a5_5a5a;

    drain(3);
    expect_word(_dut._reg_file._regs[6], 32'ha5a5_5a5a, "WB writes load result");
    expect_bit(_halted, 1'b0, "legal load sequence does not halt");

    if (_errors == 0) begin
      $display("tb_core: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
