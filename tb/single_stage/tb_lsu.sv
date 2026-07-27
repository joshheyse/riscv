// tb_lsu.sv — self-checking testbench for the word-only load/store unit.
//
//   make sim  TB=lsu
//   make wave TB=lsu
//
// Covers word-address decoding from byte addresses, combinational reads,
// clocked writes, ignored high/alignment address bits, and optional memory
// initialization from a hex file.

`timescale 1ns / 1ps

module tb_lsu
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam int unsigned DepthWords = 8;
  localparam string InitFile = "/home/josh/code/riscv-soc/tb/single_stage/tb_lsu_init.mem";

  logic        clk;
  logic        mem_write;
  word_t       addr;
  word_t       write_data;
  word_t       read_data;

  int unsigned errors = 0;
  int unsigned checks = 0;

  lsu #(
    .DepthWords(DepthWords),
    .InitFile  (InitFile)
  ) dut (
    .clk(clk),
    .mem_write(mem_write),
    .addr(addr),
    .write_data(write_data),
    .read_data(read_data)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // ------------------------------------------------------------- helpers --

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic read_addr(input word_t a, input word_t exp, input string what);
    @(negedge clk);
    mem_write = 1'b0;
    addr = a;
    #1;
    expect_word(read_data, exp, what);
  endtask

  task automatic write_addr(input word_t a, input word_t data);
    @(negedge clk);
    addr = a;
    write_data = data;
    mem_write = 1'b1;
    @(posedge clk);
    #1;
    mem_write = 1'b0;
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_lsu);
    end

    mem_write  = 1'b0;
    addr       = '0;
    write_data = '0;

    read_addr(32'h0000_0000, 32'h1111_1111, "init word at byte address 0");
    read_addr(32'h0000_0004, 32'h2222_2222, "init word at byte address 4");
    read_addr(32'h0000_0008, 32'h3333_3333, "init word at byte address 8");

    write_addr(32'h0000_000c, 32'ha5a5_5a5a);
    read_addr(32'h0000_000c, 32'ha5a5_5a5a, "write then read word at address 12");

    // Low two address bits are intentionally ignored for this word-only LSU.
    read_addr(32'h0000_000d, 32'ha5a5_5a5a, "unaligned low bits alias same word");

    // With DepthWords=8, high address bits alias by design for this tiny RAM.
    write_addr(32'h0000_0020, 32'hcafe_babe);
    read_addr(32'h0000_0000, 32'hcafe_babe, "high address bits alias same word");

    if (errors == 0) begin
      $display("tb_lsu: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_lsu: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_lsu: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
