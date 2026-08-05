`timescale 1ns / 1ps

module tb_timer_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;
  localparam word_t TimerLoAddr = 32'h1000_2000;
  localparam word_t TimerHiAddr = 32'h1000_2004;

  logic            _clk;
  logic            _rst;
  logic            _mem_valid;
  logic            _mem_write_en;
  word_t           _mem_addr;
  word_t           _mem_write_data;
  mem_write_mask_t _mem_write_mask;
  logic            _selected;
  logic            _mem_ready;
  word_t           _read_data;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic            _mem_ready_observed;
  /* verilator lint_on UNUSEDSIGNAL */
  assign _mem_ready_observed = _mem_ready;

  timer_mmio #(
    .TimerLoAddr(TimerLoAddr),
    .TimerHiAddr(TimerHiAddr)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem_valid(_mem_valid),
    .mem_write_en(_mem_write_en),
    .mem_addr(_mem_addr),
    .mem_write_data(_mem_write_data),
    .mem_write_mask(_mem_write_mask),
    .selected(_selected),
    .mem_ready(_mem_ready),
    .mem_read_data(_read_data)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

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

  task automatic set_addr(input word_t addr);
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_addr  = addr;
    #1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_timer_mmio);
    end

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_selected, 1'b0, "reset unmapped address not selected");
    expect_word(_read_data, '0, "reset unmapped address reads zero");

    set_addr(TimerLoAddr);
    expect_bit(_selected, 1'b1, "low timer address selected");
    expect_word(_read_data, '0, "reset low timer reads zero");

    @(negedge _clk);
    _rst = 1'b0;
    repeat (3) @(posedge _clk);
    #1;
    expect_word(_read_data, 32'h0000_0003, "low timer increments after reset");

    set_addr(TimerHiAddr);
    expect_bit(_selected, 1'b1, "high timer address selected");
    expect_word(_read_data, '0, "high timer initially zero");

    force _dut._counter = 64'h1234_5678_9abc_def0;
    #1;
    expect_word(_read_data, 32'h1234_5678, "high timer reads counter upper word");

    set_addr(TimerLoAddr);
    expect_word(_read_data, 32'h9abc_def0, "low timer reads counter lower word");
    release _dut._counter;

    set_addr(32'h2000_0000);
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_word(_read_data, '0, "unmapped address reads zero");

    if (errors == 0) begin
      $display("tb_timer_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_timer_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_timer_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
