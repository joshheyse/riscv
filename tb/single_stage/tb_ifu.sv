// tb_ifu.sv — self-checking testbench for the instruction fetch unit.
//
//   make sim  TB=ifu
//   make wave TB=ifu
//
// Covers the PC state machine: reset to zero, sequential increment, target
// selection for branch/jump, and returning to sequential execution afterward.

`timescale 1ns / 1ps

module tb_ifu
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;

  logic        clk;
  logic        rst;
  pc_src_t     pc_src;
  pc_t         ieu_addr;
  pc_t         pc;

  int unsigned errors = 0;
  int unsigned checks = 0;

  ifu dut (
    .clk(clk),
    .rst(rst),
    .pc_src(pc_src),
    .ieu_addr(ieu_addr),
    .pc(pc)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // ------------------------------------------------------------- helpers --

  task automatic expect_pc(input pc_t exp, input string what);
    checks++;
    if (pc !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: pc=0x%08h, expected 0x%08h", $time, what, pc, exp);
    end
  endtask

  task automatic tick(input string what, input pc_t exp);
    @(posedge clk);
    #1;
    expect_pc(exp, what);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_ifu);
    end

    rst      = 1'b1;
    pc_src   = PC_SRC_INC;
    ieu_addr = 32'h1234_5678;

    tick("reset drives pc to zero", 32'h0000_0000);
    tick("reset holds pc at zero", 32'h0000_0000);

    @(negedge clk);
    rst = 1'b0;

    tick("first sequential fetch goes to pc+4", 32'h0000_0004);
    tick("second sequential fetch goes to pc+8", 32'h0000_0008);
    tick("third sequential fetch goes to pc+12", 32'h0000_000c);

    @(negedge clk);
    pc_src   = PC_SRC_IEU_ADR;
    ieu_addr = 32'h0000_0040;
    tick("target path loads ieu_addr", 32'h0000_0040);

    @(negedge clk);
    ieu_addr = 32'h0000_0080;
    tick("target path can load a second target", 32'h0000_0080);

    @(negedge clk);
    pc_src   = PC_SRC_INC;
    ieu_addr = 32'hffff_fffc;
    tick("sequential path ignores ieu_addr", 32'h0000_0084);
    tick("sequential path continues from loaded target", 32'h0000_0088);

    @(negedge clk);
    rst      = 1'b1;
    pc_src   = PC_SRC_IEU_ADR;
    ieu_addr = 32'h0000_0200;
    tick("reset overrides target path", 32'h0000_0000);

    if (errors == 0) begin
      $display("tb_ifu: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_ifu: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_ifu: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
