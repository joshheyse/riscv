// tb_lsu.sv — self-checking testbench for the load/store unit.
//
//   make sim  TB=lsu
//   make wave TB=lsu
//
// Covers word-address decoding from byte addresses, combinational reads,
// byte/halfword/word load formatting, clocked byte/halfword/word stores,
// ignored high address bits, and optional memory initialization from a hex file.

`timescale 1ns / 1ps

module tb_lsu
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam int unsigned DepthWords = 8;
  localparam string InitFile = "/home/josh/code/riscv-soc/tb/single_stage/tb_lsu_init.mem";

  logic              clk;
  logic              rst;
  logic              mem_valid;
  logic              mem_write_en;
  logic              mem_ready;
  word_t             addr;
  word_t             write_data;
  word_t             read_mem;
  word_t             write_mem;
  word_t             read_data;
  mem_size_t         mem_size;
  logic              mem_unsigned;
  logic        [3:0] write_mask;

  int unsigned       errors = 0;
  int unsigned       checks = 0;

  lsu dut (
    .addr(addr),
    .write_data(write_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned),
    .read_mem(read_mem),
    .write_mem(write_mem),
    .write_mask(write_mask),
    .read_data(read_data)
  );

  dmem #(
    .DepthWords(DepthWords),
    .InitFile  (InitFile)
  ) dmem_i (
    .clk(clk),
    .rst(rst),
    .mem_valid(mem_valid),
    .mem_write_en(mem_write_en),
    .addr(addr),
    .write_data(write_mem),
    .write_mask(write_mask),
    .mem_ready(mem_ready),
    .read_data(read_mem)
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

  task automatic read_addr(input word_t a, input mem_size_t size, input logic unsgnd,
                           input word_t exp, input string what);
    @(negedge clk);
    mem_valid    = 1'b1;
    mem_write_en = 1'b0;
    addr         = a;
    mem_size     = size;
    mem_unsigned = unsgnd;
    @(posedge clk);
    #1;
    mem_valid = 1'b0;
    expect_word({31'b0, mem_ready}, 32'h0000_0001, {what, " ready"});
    expect_word(read_data, exp, what);
  endtask

  task automatic write_addr(input word_t a, input word_t data, input mem_size_t size);
    @(negedge clk);
    mem_valid    = 1'b1;
    addr         = a;
    write_data   = data;
    mem_size     = size;
    mem_unsigned = 1'b0;
    mem_write_en = 1'b1;
    @(posedge clk);
    #1;
    expect_word({31'b0, mem_ready}, 32'h0000_0001, "write ready");
    mem_valid = 1'b0;
    mem_write_en = 1'b0;
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_lsu);
    end

    mem_write_en = 1'b0;
    mem_valid    = 1'b0;
    rst          = 1'b1;
    addr         = '0;
    write_data   = '0;
    mem_size     = MEM_SIZE_WORD;
    mem_unsigned = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    read_addr(32'h0000_0000, MEM_SIZE_WORD, 1'b0, 32'h1111_1111, "init word at byte address 0");
    read_addr(32'h0000_0004, MEM_SIZE_WORD, 1'b0, 32'h2222_2222, "init word at byte address 4");
    read_addr(32'h0000_0008, MEM_SIZE_WORD, 1'b0, 32'h3333_3333, "init word at byte address 8");

    write_addr(32'h0000_000c, 32'ha5a5_5a5a, MEM_SIZE_WORD);
    read_addr(32'h0000_000c, MEM_SIZE_WORD, 1'b0, 32'ha5a5_5a5a,
              "write then read word at address 12");

    write_addr(32'h0000_0010, 32'h80ff_7f01, MEM_SIZE_WORD);
    read_addr(32'h0000_0010, MEM_SIZE_BYTE, 1'b0, 32'h0000_0001, "lb byte lane 0");
    read_addr(32'h0000_0011, MEM_SIZE_BYTE, 1'b0, 32'h0000_007f, "lb byte lane 1");
    read_addr(32'h0000_0012, MEM_SIZE_BYTE, 1'b0, 32'hffff_ffff, "lb sign extends byte lane 2");
    read_addr(32'h0000_0013, MEM_SIZE_BYTE, 1'b1, 32'h0000_0080, "lbu zero extends byte lane 3");
    read_addr(32'h0000_0010, MEM_SIZE_HALF, 1'b0, 32'h0000_7f01, "lh lower halfword");
    read_addr(32'h0000_0012, MEM_SIZE_HALF, 1'b0, 32'hffff_80ff, "lh sign extends upper halfword");
    read_addr(32'h0000_0012, MEM_SIZE_HALF, 1'b1, 32'h0000_80ff, "lhu zero extends upper halfword");

    write_addr(32'h0000_0014, 32'h1122_3344, MEM_SIZE_WORD);
    write_addr(32'h0000_0015, 32'h0000_00aa, MEM_SIZE_BYTE);
    read_addr(32'h0000_0014, MEM_SIZE_WORD, 1'b0, 32'h1122_aa44, "sb updates byte lane 1");
    write_addr(32'h0000_0016, 32'h0000_beef, MEM_SIZE_HALF);
    read_addr(32'h0000_0014, MEM_SIZE_WORD, 1'b0, 32'hbeef_aa44, "sh updates upper halfword");
    write_addr(32'h0000_0014, 32'h0000_cafe, MEM_SIZE_HALF);
    read_addr(32'h0000_0014, MEM_SIZE_WORD, 1'b0, 32'hbeef_cafe, "sh updates lower halfword");

    // With DepthWords=8, high address bits alias by design for this tiny RAM.
    write_addr(32'h0000_0020, 32'hcafe_babe, MEM_SIZE_WORD);
    read_addr(32'h0000_0000, MEM_SIZE_WORD, 1'b0, 32'hcafe_babe,
              "high address bits alias same word");

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
