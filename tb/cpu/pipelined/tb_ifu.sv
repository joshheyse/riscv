// tb_ifu.sv - directed _checks for the pipelined instruction fetch unit.
//
//   make sim DESIGN=pipelined TB=ifu
//   make wave DESIGN=pipelined TB=ifu
//
// The bus splits acceptance from response: a request transfers on the edge
// where `req.valid` and `req_ready` are both high, and the data arrives later
// on `rsp.valid`. So the IFU takes its request off the bus as soon as it is
// accepted, and tracks the outstanding response separately -- a request left
// asserted after acceptance would be offering a transaction already taken.

`timescale 1ns / 1ps

module tb_ifu
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 60;

  localparam instr_t AddiX1 = 32'h0050_0093;  // addi x1, x0, 5
  localparam instr_t AddX1 = 32'h0031_00b3;  // add  x1, x2, x3
  localparam instr_t WrongPath = 32'hffff_ffff;

  logic      _clk;
  logic      _rst;
  logic      _fetch_en;
  redirect_t _redirect;
  pc_t       _pc;
  if_id_t    _fetched;

  /* verilator lint_off UNUSEDSIGNAL */
  vmem_if _ibus (
    _clk,
    _rst
  );
  /* verilator lint_on UNUSEDSIGNAL */

  int unsigned _errors = 0;
  int unsigned _checks = 0;
  int unsigned _waits;

  // A conforming slave: it accepts when `_accept_en` is set, and answers each
  // accepted request exactly once, `_rsp_delay` cycles later. Holding
  // `rsp.valid` across cycles, or answering with nothing outstanding, is what
  // the interface assertions exist to catch.
  logic        _accept_en;
  int unsigned _rsp_delay;
  instr_t      _next_instr;
  mmu_fault_t  _next_fault;
  logic        _slave_accept;
  int unsigned _pending;
  instr_t      _pending_instr;
  mmu_fault_t  _pending_fault;

  assign _ibus.req_ready = _accept_en;
  assign _slave_accept   = _ibus.req.valid && _ibus.req_ready;

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _ibus.rsp <= '0;
      _pending  <= 0;
    end else begin
      _ibus.rsp.valid <= 1'b0;
      if (_pending != 0) begin
        _pending <= _pending - 1;
        if (_pending == 1) begin
          _ibus.rsp.valid     <= 1'b1;
          _ibus.rsp.read_data <= _pending_instr;
          _ibus.rsp.fault     <= _pending_fault;
        end
      end else if (_slave_accept) begin
        if (_rsp_delay == 0) begin
          _ibus.rsp.valid     <= 1'b1;
          _ibus.rsp.read_data <= _next_instr;
          _ibus.rsp.fault     <= _next_fault;
        end else begin
          _pending       <= _rsp_delay;
          _pending_instr <= _next_instr;
          _pending_fault <= _next_fault;
        end
      end
    end
  end

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
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic step_to_request(input pc_t addr, input string what);
    _waits = 0;
    while (!(_ibus.req.valid && _ibus.req.addr == addr) && _waits < 12) begin
      @(posedge _clk);
      #1;
      _waits++;
    end
    expect_bit(_ibus.req.valid, 1'b1, {what, " is presented"});
    expect_word(_ibus.req.addr, addr, {what, " address"});
  endtask

  task automatic step_to_fetch(input pc_t addr, input string what);
    _waits = 0;
    while (!(_fetched.valid && _fetched.slot.pc == addr) && _waits < 12) begin
      @(posedge _clk);
      #1;
      _waits++;
    end
    expect_bit(_fetched.valid, 1'b1, {what, " completes"});
    expect_word(_fetched.slot.pc, addr, {what, " records pc"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_ifu);
    end

    _accept_en = 1'b0;
    _rsp_delay = 1;
    _next_instr = AddiX1;
    _next_fault = MMU_FAULT_NONE;
    _fetch_en = 1'b1;
    _redirect = '0;
    _rst = 1'b1;

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0000, "reset clears pc");
    expect_bit(_fetched.valid, 1'b0, "reset clears fetched valid");
    expect_bit(_ibus.req.valid, 1'b0, "reset suppresses instruction request");

    @(negedge _clk);
    _rst = 1'b0;

    // ---- a refused request is held, unchanged, until it is accepted -------
    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "first request is presented");
    expect_word(_ibus.req.addr, 32'h0000_0000, "first request starts at pc zero");
    expect_word(_pc, 32'h0000_0004, "issuing the first request advances pc");

    repeat (3) begin
      @(posedge _clk);
      #1;
      expect_bit(_ibus.req.valid, 1'b1, "refused request stays presented");
      expect_word(_ibus.req.addr, 32'h0000_0000, "refused request holds its address");
      expect_word(_pc, 32'h0000_0004, "refused request does not advance pc again");
      expect_bit(_fetched.valid, 1'b0, "refused request produces no fetch");
    end

    // ---- acceptance takes it off the bus, the response comes later --------
    @(negedge _clk);
    _accept_en = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b0, "accepted request leaves the bus");
    expect_bit(_fetched.valid, 1'b0, "acceptance alone does not produce a fetch");

    @(negedge _clk);
    _next_instr = AddX1;

    step_to_fetch(32'h0000_0000, "first fetch");
    expect_word(_fetched.slot.instr.raw, AddiX1, "first fetch records instruction");

    // ---- fetch_en low holds the buffered entry ---------------------------
    @(negedge _clk);
    _fetch_en = 1'b0;
    repeat (3) begin
      @(posedge _clk);
      #1;
      expect_bit(_fetched.valid, 1'b1, "pipe disabled holds fetched output");
      expect_word(_fetched.slot.instr.raw, AddiX1, "held fetch keeps instruction");
      expect_bit(_ibus.req.valid, 1'b0, "pipe disabled issues no request");
    end

    @(negedge _clk);
    _fetch_en = 1'b1;

    step_to_fetch(32'h0000_0004, "second fetch");
    expect_word(_fetched.slot.instr.raw, AddX1, "second fetch records instruction");

    // ---- redirect while a response is outstanding ------------------------
    // The request was accepted already, so there is nothing to withdraw; the
    // wrong-path response must simply be discarded.
    @(negedge _clk);
    _next_instr = WrongPath;
    step_to_request(32'h0000_0008, "wrong-path request");

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b0, "wrong-path request is accepted, not re-presented");

    @(negedge _clk);
    _redirect.valid = 1'b1;
    _redirect.pc = 32'h0000_0040;
    _next_instr = 32'h0000_0093;  // addi x1, x0, 0

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0040, "redirect loads target pc");
    expect_bit(_fetched.valid, 1'b0, "redirect squashes the buffered entry");

    @(negedge _clk);
    _redirect.valid = 1'b0;

    step_to_fetch(32'h0000_0040, "redirected fetch");
    expect_word(_fetched.slot.instr.raw, 32'h0000_0093, "redirected fetch records instruction");

    // ---- a zero-latency slave may accept and answer in one cycle ---------
    @(negedge _clk);
    _rsp_delay  = 0;
    _next_instr = 32'h0010_0093;  // addi x1, x0, 1

    step_to_fetch(32'h0000_0044, "zero-latency fetch");
    expect_word(_fetched.slot.instr.raw, 32'h0010_0093, "zero-latency fetch records instruction");

    // ---- translation failures travel atomically with the faulting fetch --
    @(negedge _clk);
    _next_fault = MMU_FAULT_PAGE;
    step_to_fetch(32'h0000_0048, "instruction page fault");
    expect_bit(_fetched.trap_req.valid, 1'b1, "page fault marks fetch trap valid");
    expect_word(word_t'(_fetched.trap_req.src), word_t'(TRAP_SRC_INSTR_PAGE_FAULT),
                "page fault source");
    expect_word(_fetched.trap_req.tval, 32'h0000_0048, "page fault virtual address");

    @(negedge _clk);
    _next_fault = MMU_FAULT_ACCESS;
    step_to_fetch(32'h0000_004c, "instruction access fault");
    expect_bit(_fetched.trap_req.valid, 1'b1, "access fault marks fetch trap valid");
    expect_word(word_t'(_fetched.trap_req.src), word_t'(TRAP_SRC_INSTR_ACCESS_FAULT),
                "access fault source");
    expect_word(_fetched.trap_req.tval, 32'h0000_004c, "access fault virtual address");

    if (_errors == 0) begin
      $display("tb_ifu: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_ifu: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_ifu: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
