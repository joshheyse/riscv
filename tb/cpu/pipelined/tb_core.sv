// tb_core.sv - smoke test for the pipelined core over the unified memory port.
//
//   make sim DESIGN=pipelined TB=core
//   make wave DESIGN=pipelined TB=core
//
// `core` presents one memory port: `mem_arbiter` interleaves instruction
// fetches and data accesses behind it, and both L1 caches are pure bypass at
// the core's default (empty) cacheable range. The two streams therefore share a
// single slave, and an unanswered fetch holds the arbiter -- so this testbench
// serves the bus from a backing model rather than hand-feeding one stream.
//
// The streams are still observed separately, at the IFU and LSU ports where the
// old split `ibus`/`dbus` used to sit.

`timescale 1ns / 1ps

module tb_core
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 600;
  localparam mem_addr_t LoadAddr = 32'h1000_0000;

  logic        _clk;
  logic        _rst;
  logic        _halted;
  pc_t         _pc;

  int unsigned _mmio_wait;
  mem_data_t   _mmio_read_data;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        _mmio_write;
  mem_addr_t   _mmio_write_addr;
  mem_data_t   _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem ();
  irq_if _irq ();

  always_comb begin
    _irq.pending.platform = 16'h0000;
    _irq.pending.meip = 1'b0;
    _irq.pending.seip = 1'b0;
    _irq.pending.mtip = 1'b0;
    _irq.pending.stip = 1'b0;
    _irq.pending.msip = 1'b0;
    _irq.pending.ssip = 1'b0;
    _irq.pending.usip = 1'b0;
  end

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  tb_core_bus #(
    .Words(64)
  ) _bus (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .mmio_wait(_mmio_wait),
    .mmio_read_data(_mmio_read_data),
    .mmio_write(_mmio_write),
    .mmio_write_addr(_mmio_write_addr),
    .mmio_write_data(_mmio_write_data)
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

  // Fill the whole program window with a chosen filler so the core keeps
  // fetching legal instructions past the end of the sequence under test.
  task automatic load_program(input instr_t filler);
    for (int unsigned word_idx = 0; word_idx < 64; word_idx++) begin
      _bus._store[word_idx] = filler;
    end
  endtask

  task automatic reset_core(input string what);
    @(negedge _clk);
    _rst = 1'b1;
    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, {what, " reset does not halt"});
    expect_word(_pc, 32'h0000_0000, {what, " reset pc"});

    @(negedge _clk);
    _rst = 1'b0;
    #1;
  endtask

  task automatic drain(input int unsigned cycles);
    repeat (cycles) begin
      @(posedge _clk);
      #1;
    end
  endtask

  // Advance until the LSU asserts a request, so the load checks below do not
  // depend on the exact bypass latency of the L1 data cache.
  task automatic wait_lsu_req(input string what);
    int unsigned waits;
    waits = 0;
    #1;
    while (!_dut._data_lsu_cache.req.valid && waits < 60) begin
      waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._data_lsu_cache.req.valid, 1'b1, {what, " reaches the LSU port"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core);
    end

    _rst = 1'b1;
    _mmio_wait = 0;
    _mmio_read_data = '0;

    // ---- ALU sequence -------------------------------------------------
    load_program(32'h0000_0013);  // nop
    _bus._store[0] = 32'h0050_0093;  // addi x1,x0,5
    _bus._store[1] = 32'h0031_8233;  // add  x4,x3,x3

    reset_core("alu");
    _dut._reg_file._regs[2] = 32'h1111_2222;
    _dut._reg_file._regs[3] = 32'h3333_4444;

    drain(40);
    expect_word(_dut._reg_file._regs[1], 32'h0000_0005, "WB writes addi result");
    expect_word(_dut._reg_file._regs[4], 32'h6666_8888, "WB writes add result");
    expect_bit(_halted, 1'b0, "legal ALU sequence does not halt");

    // ---- Load with a stalled data response ----------------------------
    // Only MMIO is stalled. Fetches must keep completing, because an
    // unanswered fetch would hold the arbiter and starve the load entirely.
    load_program(32'h0000_0013);  // nop
    _bus._store[0] = 32'h0001_2303;  // lw x6,0(x2)

    reset_core("load");
    _dut._reg_file._regs[2] = LoadAddr;
    _dut._reg_file._regs[6] = 32'h0000_0000;
    _mmio_wait = 40;
    _mmio_read_data = 32'ha5a5_5a5a;

    wait_lsu_req("load");
    expect_bit(_dut._data_lsu_cache.req.write_en, 1'b0, "load request is read");
    expect_word(_dut._data_lsu_cache.req.addr, LoadAddr, "load request address");
    expect_bit(_dut._pipe_ctrl.fetch == STAGE_HOLD, 1'b1, "load holds fetch while dbus not ready");

    @(posedge _clk);
    #1;
    expect_bit(_dut._data_lsu_cache.req.valid, 1'b1, "load keeps request valid while stalled");
    expect_word(_dut._data_lsu_cache.req.addr, LoadAddr, "load keeps address stable while stalled");

    @(negedge _clk);
    _mmio_wait = 0;

    drain(20);
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
