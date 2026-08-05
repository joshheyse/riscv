// tb_ifu.sv - directed checks for the pipelined instruction fetch unit.
//
//   make sim DESIGN=pipelined TB=ifu
//   make wave DESIGN=pipelined TB=ifu

`timescale 1ns / 1ps

module tb_ifu
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 20;

  logic      _clk;
  logic      _rst;
  logic      _fetch_en;
  redirect_t _redirect;
  pc_t       _pc;
  if_id_t    _fetched;

  /* verilator lint_off UNUSEDSIGNAL */
  ibus_if _ibus ();
  /* verilator lint_on UNUSEDSIGNAL */

  int unsigned errors = 0;
  int unsigned checks = 0;

  ifu _dut (
    .clk(_clk),
    .rst(_rst),
    .fetch_en(_fetch_en),
    .redirect(_redirect),
    .pc(_pc),
    .fetched(_fetched),
    .ibus(_ibus)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_ifu);
    end

    _ibus.rsp = '0;
    _fetch_en = 1'b1;
    _redirect = '0;
    _rst = 1'b1;

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0000, "reset clears pc");
    expect_bit(_fetched.valid, 1'b0, "reset clears fetched valid");
    expect_bit(_ibus.req.valid, 1'b0, "reset suppresses instruction request");
    expect_word(_ibus.req.addr, 32'h0000_0000, "reset request address is zero");

    @(negedge _clk);
    _rst = 1'b0;
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr.raw = 32'h0050_0093;  // addi x1, x0, 5
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "pipe enabled requests instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "first request starts at pc zero");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "not-ready response does not produce fetch");
    expect_word(_pc, 32'h0000_0004, "first request issue advances pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b1, "ready response produces fetch");
    expect_word(_fetched.pc, 32'h0000_0000, "first fetch records pc");
    expect_word(_fetched.instr.raw, 32'h0050_0093, "first fetch records instruction");
    expect_word(_pc, 32'h0000_0004, "accepted fetch keeps next request pc");
    expect_word(_ibus.req.addr, 32'h0000_0004, "next request uses advanced pc");

    @(negedge _clk);
    _fetch_en = 1'b0;
    _ibus.rsp.instr.raw = 32'h0031_00b3;  // add x1, x2, x3
    #1;
    expect_bit(_ibus.req.valid, 1'b0, "pipe disabled suppresses instruction request");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b1, "pipe disabled holds fetched output");
    expect_word(_fetched.pc, 32'h0000_0000, "held fetch keeps pc");
    expect_word(_fetched.instr.raw, 32'h0050_0093, "held fetch keeps instruction");
    expect_word(_pc, 32'h0000_0004, "pipe disabled holds pc");

    @(negedge _clk);
    _fetch_en = 1'b1;
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "reenabled pipe requests instruction");
    expect_word(_ibus.req.addr, 32'h0000_0004, "reenabled request resumes held pc");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "reenabled pipe issues before response is accepted");
    expect_word(_pc, 32'h0000_0008, "second request issue advances pc");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b1, "second ready response produces fetch");
    expect_word(_fetched.pc, 32'h0000_0004, "second fetch records held pc");
    expect_word(_fetched.instr.raw, 32'h0031_00b3, "second fetch records instruction");
    expect_word(_pc, 32'h0000_0008, "second accepted fetch keeps next request pc");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "wrong-path request issues before redirect");
    expect_word(_pc, 32'h0000_000c, "wrong-path request advances pc before redirect");

    @(negedge _clk);
    _redirect.valid = 1'b1;
    _redirect.pc = 32'h0000_0040;
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr.raw = 32'hffff_ffff;

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "redirect squashes old fetch response");
    expect_word(_pc, 32'h0000_0040, "redirect loads target pc");
    expect_word(_ibus.req.addr, 32'h0000_0040, "redirect request uses target pc");

    @(negedge _clk);
    _redirect.valid = 1'b0;
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'hffff_ffff;

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "post-redirect stale response is ignored");
    expect_word(_pc, 32'h0000_0040, "stale response after redirect does not advance pc");
    expect_word(_ibus.req.addr, 32'h0000_0040, "stale response keeps target request active");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0000_0093;  // addi x1, x0, 0

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "post-redirect target request issues before response");
    expect_word(_pc, 32'h0000_0044, "post-redirect target request advances pc");

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b1, "post-redirect ready response produces fetch");
    expect_word(_fetched.pc, 32'h0000_0040, "post-redirect fetch records target pc");
    expect_word(_fetched.instr.raw, 32'h0000_0093, "post-redirect fetch records instruction");
    expect_word(_pc, 32'h0000_0044, "post-redirect fetch keeps next request pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_fetched.valid, 1'b0, "ready low clears fetched output");
    expect_word(_pc, 32'h0000_0048, "ready low next request issue advances pc");
    expect_bit(_ibus.req.valid, 1'b0, "outstanding request suppresses duplicate request");
    expect_word(_ibus.req.addr, 32'h0000_0048, "pending request leaves next pc on address bus");

    if (errors == 0) begin
      $display("tb_ifu: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_ifu: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_ifu: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
