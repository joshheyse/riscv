`timescale 1ns / 1ps

module tb_clint_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;
  localparam word_t ClintMsipAddr = 32'h1000_2008;
  localparam word_t ClintMtimecmpLoAddr = 32'h1000_2010;
  localparam word_t ClintMtimecmpHiAddr = 32'h1000_2014;
  localparam word_t ClintMtimeLoAddr = 32'h1000_2018;
  localparam word_t ClintMtimeHiAddr = 32'h1000_201c;

  logic            _clk;
  logic            _rst;
  logic            _mem_valid;
  logic            _mem_write_en;
  word_t           _mem_addr;
  word_t           _mem_write_data;
  mem_write_mask_t _mem_write_mask;

  word_t           _read_data;

  logic            _selected;
  logic            _mem_ready;
  mem_if _mem ();
  irq_if _irq ();

  int unsigned errors = 0;
  int unsigned checks = 0;
  word_t       _mtime_before;
  word_t       _mtime_after;

  clint #(
    .MsipAddr(ClintMsipAddr),
    .MtimecmpLoAddr(ClintMtimecmpLoAddr),
    .MtimecmpHiAddr(ClintMtimecmpHiAddr),
    .MtimeLoAddr(ClintMtimeLoAddr),
    .MtimeHiAddr(ClintMtimeHiAddr)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .selected(_selected),
    .irq(_irq)
  );

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;
  assign _mem_ready = _mem.rsp.ready;
  assign _read_data = _mem.rsp.read_data;

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic mem_write(input word_t addr, input word_t data, input logic exp_ready,
                           input logic exp_selected, input string what);
    @(negedge _clk);
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b1;
    _mem_addr       = addr;
    _mem_write_data = data;
    _mem_write_mask = 4'hf;

    @(posedge _clk);
    #1;
    expect_bit(_selected, exp_selected, {what, " selected"});
    expect_bit(_mem_ready, exp_ready, {what, " ready"});

    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
  endtask

  task automatic mem_read(input word_t addr, input logic exp_ready, input logic exp_selected,
                          input word_t exp_data, input string what);
    @(negedge _clk);
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b0;
    _mem_addr       = addr;
    _mem_write_data = '0;
    _mem_write_mask = 4'hf;

    @(posedge _clk);
    #1;
    expect_bit(_selected, exp_selected, {what, " selected"});
    expect_bit(_mem_ready, exp_ready, {what, " ready"});
    expect_word(_read_data, exp_data, what);

    _mem_valid = 1'b0;
    _mem_addr = '0;
    _mem_write_data = '0;
    _mem_write_mask = 4'hf;
  endtask

  task automatic expect_irq(input logic exp_msip, input logic exp_mtip, input string what);
    checks++;
    if (_irq.pending.msip !== exp_msip ||
        _irq.pending.mtip !== exp_mtip ||
        _irq.pending.meip !== 1'b0 ||
        _irq.pending.seip !== 1'b0 ||
        _irq.pending.stip !== 1'b0 ||
        _irq.pending.ssip !== 1'b0 ||
        _irq.pending.platform !== 16'h0 ||
        _irq.pending.usip !== 1'b0) begin
      errors++;
      $display(
          "  FAIL [%0t] %s: got (meip,seip,mtip,stip,msip,ssip,usip,platform)=(%b,%b,%b,%b,%b,%b,%b,0x%04h) expected msip=%b mtip=%b",
          $time, what, _irq.pending.meip, _irq.pending.seip, _irq.pending.mtip, _irq.pending.stip,
          _irq.pending.msip, _irq.pending.ssip, _irq.pending.usip, _irq.pending.platform, exp_msip,
          exp_mtip);
    end
  endtask

  task automatic mem_read_capture(input word_t addr, input logic exp_ready,
                                  input logic exp_selected, input string what, output word_t data);
    @(negedge _clk);
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b0;
    _mem_addr       = addr;
    _mem_write_data = '0;
    _mem_write_mask = 4'hf;

    @(posedge _clk);
    #1;
    expect_bit(_selected, exp_selected, {what, " selected"});
    expect_bit(_mem_ready, exp_ready, {what, " ready"});
    data            = _read_data;

    _mem_valid      = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = 4'hf;
  endtask

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_clint_mmio);
    end

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;

    repeat (2) @(posedge _clk);
    #1;

    // Unmapped access should not be selected and should not present ready.
    mem_read(32'h1000_3000, 1'b0, 1'b0, '0, "unmapped read");

    // Initial values after reset.
    mem_read(ClintMsipAddr, 1'b1, 1'b1, 32'h0000_0000, "msip reset is zero");
    mem_read(ClintMtimecmpLoAddr, 1'b1, 1'b1, 32'hffff_ffff, "mtimecmp_lo reset all ones");
    mem_read(ClintMtimecmpHiAddr, 1'b1, 1'b1, 32'hffff_ffff, "mtimecmp_hi reset all ones");
    mem_read(ClintMtimeLoAddr, 1'b1, 1'b1, 32'h0000_0000, "mtime_lo reset zero");
    mem_read(ClintMtimeHiAddr, 1'b1, 1'b1, 32'h0000_0000, "mtime_hi reset zero");

    @(negedge _clk);
    _rst = 1'b0;

    // msip should become a one-shot software-settable pending bit.
    mem_write(ClintMsipAddr, 32'h0000_0001, 1'b1, 1'b1, "msip write");
    mem_read(ClintMsipAddr, 1'b1, 1'b1, 32'h0000_0001, "msip readback");
    expect_bit(_irq.pending.msip, 1'b1, "msip pending bit");
    expect_irq(1'b1, 1'b0, "interrupt pending after msip write");

    // Set a near-term timer compare so mtip eventually asserts.
    mem_write(ClintMtimecmpLoAddr, 32'h0000_0004, 1'b1, 1'b1, "mtimecmp_lo write");
    mem_write(ClintMtimecmpHiAddr, 32'h0000_0000, 1'b1, 1'b1, "mtimecmp_hi write");
    mem_read(ClintMtimecmpLoAddr, 1'b1, 1'b1, 32'h0000_0004, "mtimecmp_lo readback");
    mem_read(ClintMtimecmpHiAddr, 1'b1, 1'b1, 32'h0000_0000, "mtimecmp_hi readback");

    // Wait for timer to reach the compare value; with a running 32-bit counter this should happen soon.
    repeat (10) @(posedge _clk);
    #1;
    expect_bit(_irq.pending.mtip, 1'b1, "mtip pending asserted once time reached");

    // Writing mtime is ignored.
    mem_read_capture(ClintMtimeLoAddr, 1'b1, 1'b1, "mtime_lo before forbidden write",
                     _mtime_before);
    mem_write(ClintMtimeLoAddr, 32'h0000_0000, 1'b1, 1'b1, "mtime_lo write ignored in DUT");
    mem_read_capture(ClintMtimeLoAddr, 1'b1, 1'b1, "mtime_lo after forbidden write", _mtime_after);

    if (!(_mtime_after > _mtime_before)) begin
      errors++;
      $display(
          "  FAIL [%0t] mtime_lo should progress while write ignored, before=0x%08h after=0x%08h",
          $time, _mtime_before, _mtime_after);
    end
    checks++;

    if (errors == 0) begin
      $display("tb_clint_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_clint_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_clint_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
