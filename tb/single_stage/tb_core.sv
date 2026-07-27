// tb_core.sv — self-checking smoke test for the integrated single-cycle core.
//
//   make sim  TB=core
//   make wave TB=core
//
// Runs a tiny hand-encoded RV32I program from instruction memory and checks the
// integrated fetch/decode/execute/load/store path. Internal register-file and
// data-memory state is checked hierarchically because the core's public
// interface deliberately exposes only fetch/debug signals.

`timescale 1ns / 1ps

module tb_core
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam string ProgramFile = "/home/josh/code/riscv-soc/tb/single_stage/tb_core_smoke.mem";

  logic        clk;
  logic        rst;
  pc_t         pc;
  instr_u      instr;

  int unsigned errors = 0;
  int unsigned checks = 0;

  core #(
    .ImemDepthWords(16),
    .ImemInitFile  (ProgramFile)
  ) dut (
    .clk(clk),
    .rst(rst),
    .pc(pc),
    .instr(instr)
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

  task automatic step(input string what);
    @(posedge clk);
    #1;
    $display("tb_core: %-28s pc=0x%08h instr=0x%08h", what, pc, instr.raw);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core);
    end

    rst = 1'b1;
    step("reset");
    expect_word(pc, 32'h0000_0000, "reset pc");

    @(negedge clk);
    rst = 1'b0;

    step("addi x1,x0,5");
    step("addi x2,x0,7");
    step("add x3,x1,x2");
    step("sw x3,0(x0)");
    step("lw x4,0(x0)");
    step("beq x4,x3,+8");
    step("addi x5,x0,2");
    step("sw x5,4(x0)");
    step("jal x0,0");
    step("jal x0,0 again");

    expect_word(pc, 32'h0000_0024, "jal holds pc at loop address");
    expect_word(dut.d.regfile.regs[1], 32'h0000_0005, "x1 = 5");
    expect_word(dut.d.regfile.regs[2], 32'h0000_0007, "x2 = 7");
    expect_word(dut.d.regfile.regs[3], 32'h0000_000c, "x3 = 12");
    expect_word(dut.d.regfile.regs[4], 32'h0000_000c, "x4 loaded 12");
    expect_word(dut.d.regfile.regs[5], 32'h0000_0002, "x5 branch target value");
    expect_word(dut.l.memory[0], 32'h0000_000c, "dmem[0] stored x3");
    expect_word(dut.l.memory[1], 32'h0000_0002, "dmem[1] stored x5");

    if (errors == 0) begin
      $display("tb_core: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_core: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_core: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
