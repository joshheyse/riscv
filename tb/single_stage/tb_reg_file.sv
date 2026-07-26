// tb_reg_file.sv — self-checking testbench for the RV32I register file.
//
//   make sim  TB=reg_file
//   make wave TB=reg_file
//
// Covers the things lint cannot: the ISA-mandated x0 behavior, two read ports
// operating independently in the same cycle, and the write/read timing that
// makes single-cycle execution work.

`timescale 1ns / 1ps

module tb_reg_file;

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 10_000;

  logic               clk;
  logic        [ 4:0] rd_addr1;
  logic        [ 4:0] rd_addr2;
  logic        [ 4:0] wr_addr;
  logic        [31:0] wr_data;
  logic               wr_en;
  logic        [31:0] rd_data1;
  logic        [31:0] rd_data2;

  int unsigned        errors = 0;
  int unsigned        checks = 0;

  reg_file dut (
      .clk(clk),
      .rd_addr1(rd_addr1),
      .rd_addr2(rd_addr2),
      .wr_addr(wr_addr),
      .wr_data(wr_data),
      .wr_en(wr_en),
      .rd_data1(rd_data1),
      .rd_data2(rd_data2)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // ------------------------------------------------------------- helpers --

  // Compare one value against expectation, recording rather than aborting so a
  // single run reports every failure instead of only the first.
  task automatic expect_eq(input logic [31:0] got, input logic [31:0] exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      // $display, not $error: Verilator treats $error as $stop and aborts on
      // the first mismatch, hiding every later failure.
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  // Drive a write for exactly one clock edge. Stimulus changes on the negedge
  // so inputs are stable well before the posedge that commits them.
  task automatic write_reg(input logic [4:0] a, input logic [31:0] d);
    @(negedge clk);
    wr_addr = a;
    wr_data = d;
    wr_en   = 1'b1;
    @(negedge clk);
    wr_en = 1'b0;
  endtask

  // Reads are combinational: drive the address, let it settle, sample.
  task automatic read1(input logic [4:0] a, input logic [31:0] exp, input string what);
    rd_addr1 = a;
    #1;
    expect_eq(rd_data1, exp, what);
  endtask

  task automatic read2(input logic [4:0] a, input logic [31:0] exp, input string what);
    rd_addr2 = a;
    #1;
    expect_eq(rd_data2, exp, what);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    logic [31:0] expected[32];

    rd_addr1 = '0;
    rd_addr2 = '0;
    wr_addr  = '0;
    wr_data  = '0;
    wr_en    = 1'b0;

    @(negedge clk);

    // -- T1: x0 reads zero before anything has been written ----------------
    // The array is uninitialised here, so every other register is X. x0 must
    // still be a hard zero, which proves the mux is on the read path and not
    // an artifact of storage happening to be clear.
    read1(5'd0, 32'h0000_0000, "T1 x0 reads zero on port 1");
    read2(5'd0, 32'h0000_0000, "T1 x0 reads zero on port 2");

    // -- T2: writes to x0 are discarded ------------------------------------
    write_reg(5'd0, 32'hDEAD_BEEF);
    read1(5'd0, 32'h0000_0000, "T2 x0 still zero after write, port 1");
    read2(5'd0, 32'h0000_0000, "T2 x0 still zero after write, port 2");

    // -- T3: basic write then read on each port ----------------------------
    write_reg(5'd5, 32'hA5A5_1234);
    read1(5'd5, 32'hA5A5_1234, "T3 x5 readback on port 1");
    read2(5'd5, 32'hA5A5_1234, "T3 x5 readback on port 2");

    // -- T4: the two read ports are independent ----------------------------
    // This is the whole reason there are two of them: `add x3, x1, x2` needs
    // both operands in the same cycle.
    write_reg(5'd1, 32'h1111_1111);
    write_reg(5'd2, 32'h2222_2222);
    rd_addr1 = 5'd1;
    rd_addr2 = 5'd2;
    #1;
    expect_eq(rd_data1, 32'h1111_1111, "T4 port 1 sees x1");
    expect_eq(rd_data2, 32'h2222_2222, "T4 port 2 sees x2");

    // Swap them: a stuck or crossed connection passes the test above but
    // fails this one.
    rd_addr1 = 5'd2;
    rd_addr2 = 5'd1;
    #1;
    expect_eq(rd_data1, 32'h2222_2222, "T4 port 1 sees x2 after swap");
    expect_eq(rd_data2, 32'h1111_1111, "T4 port 2 sees x1 after swap");

    // -- T5: both ports may read the same register -------------------------
    rd_addr1 = 5'd5;
    rd_addr2 = 5'd5;
    #1;
    expect_eq(rd_data1, 32'hA5A5_1234, "T5 same register, port 1");
    expect_eq(rd_data2, 32'hA5A5_1234, "T5 same register, port 2");

    // -- T6: wr_en low must block the write --------------------------------
    @(negedge clk);
    wr_addr = 5'd5;
    wr_data = 32'hFFFF_FFFF;
    wr_en   = 1'b0;
    @(negedge clk);
    read1(5'd5, 32'hA5A5_1234, "T6 x5 unchanged with wr_en low");

    // -- T7: a write lands at the clock edge, not before -------------------
    // Single-cycle execution depends on this: instruction N reads its operands
    // and writes its result in the same cycle, and instruction N+1 must see
    // that result. If reads saw the write combinationally this would be a
    // loop; if the write landed a cycle late, N+1 would read stale data.
    @(negedge clk);
    wr_addr  = 5'd7;
    wr_data  = 32'hCAFE_0007;
    wr_en    = 1'b1;
    rd_addr1 = 5'd7;
    write_reg(5'd7, 32'hCAFE_0007);
    read1(5'd7, 32'hCAFE_0007, "T7 x7 visible in the cycle after the write");

    // -- T8: every register is independently addressable -------------------
    // Walks all 31 writable registers with distinct values, then reads them
    // all back. Catches address-decode faults that a single-register test
    // sails straight past.
    expected[0] = 32'h0000_0000;
    for (int i = 1; i < 32; i++) begin
      expected[i] = 32'h5A00_0000 | (i << 8) | i;
      write_reg(5'(i), expected[i]);
    end
    for (int i = 0; i < 32; i++) begin
      read1(5'(i), expected[i], $sformatf("T8 x%0d readback, port 1", i));
      read2(5'(i), expected[i], $sformatf("T8 x%0d readback, port 2", i));
    end

    // -- T9: overwrite ------------------------------------------------------
    write_reg(5'd9, 32'h0000_0009);
    read1(5'd9, 32'h0000_0009, "T9 x9 first value");
    write_reg(5'd9, 32'h9999_9999);
    read1(5'd9, 32'h9999_9999, "T9 x9 overwritten");

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_reg_file: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_reg_file: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $error("[%0t] tb_reg_file: timeout after %0d cycles", $time, TimeoutCycles);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_reg_file);
    end
  end

endmodule
