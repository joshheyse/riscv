// tb_core.sv — self-checking smoke test for the integrated single-cycle core.
//
//   make sim  TB=core
//   make wave TB=core
//
// Runs a tiny RV32I program through the minimal SoC wrapper and checks the
// integrated fetch/decode/execute/load/store path. Internal
// register-file and data-memory state is checked hierarchically because the
// public interface deliberately exposes only fetch/debug signals.

`timescale 1ns / 1ps

module tb_core
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam string ProgramFile = "/home/josh/code/riscv-soc/tb/single_stage/tb_core_load_store.mem";

  logic        _clk;
  logic        _rst;
  pc_t         _pc;
  pc_t         _imem_addr;
  instr_u      _instr;
  logic        _halted;

  int unsigned errors = 0;
  int unsigned checks = 0;

  soc #(
    .ImemDepthWords(32),
    .ImemInitFile(ProgramFile)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .pc(_pc),
    .imem_addr(_imem_addr),
    .instr(_instr),
    .halted(_halted)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  // ------------------------------------------------------------- helpers --

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

  task automatic step(input string what);
    @(posedge _clk);
    #1;
    $display("tb_core: %-28s pc=0x%08h imem_addr=0x%08h instr=0x%08h", what, _pc, _imem_addr,
             _instr.raw);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core);
    end

    _rst = 1'b1;
    step("reset");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;

    step("addi x1,x0,0");
    step("addi x2,x0,-1");
    step("sw x2,0(x1)");
    step("sw x2,0(x1) complete");
    step("addi x3,x0,127");
    step("sb x3,1(x1)");
    step("sb x3,1(x1) complete");
    step("lb x4,1(x1)");
    step("lb x4,1(x1) complete");
    step("lb x5,2(x1)");
    step("lb x5,2(x1) complete");
    step("lbu x6,2(x1)");
    step("lbu x6,2(x1) complete");
    step("lui x7,0x8");
    step("addi x7,x7,1");
    step("sh x7,2(x1)");
    step("sh x7,2(x1) complete");
    step("lh x8,2(x1)");
    step("lh x8,2(x1) complete");
    step("lhu x9,2(x1)");
    step("lhu x9,2(x1) complete");
    step("lw x10,0(x1)");
    step("lw x10,0(x1) complete");
    step("sw x10,4(x1)");
    step("sw x10,4(x1) complete");
    step("jal x0,0");
    step("jal fallthrough bubble");
    step("jal x0,0 again");

    expect_bit(_halted, 1'b0, "legal core smoke program does not halt");
    expect_word(_pc, 32'h0000_003c, "jal holds pc at loop address");
    expect_word(_dut._core._datapath._regfile._regs[1], 32'h0000_0000, "x1 = dmem base");
    expect_word(_dut._core._datapath._regfile._regs[2], 32'hffff_ffff, "x2 = -1");
    expect_word(_dut._core._datapath._regfile._regs[3], 32'h0000_007f, "x3 = byte store value");
    expect_word(_dut._core._datapath._regfile._regs[4], 32'h0000_007f, "x4 = lb positive byte");
    expect_word(_dut._core._datapath._regfile._regs[5], 32'hffff_ffff,
                "x5 = lb sign-extended byte");
    expect_word(_dut._core._datapath._regfile._regs[6], 32'h0000_00ff,
                "x6 = lbu zero-extended byte");
    expect_word(_dut._core._datapath._regfile._regs[7], 32'h0000_8001, "x7 = halfword store value");
    expect_word(_dut._core._datapath._regfile._regs[8], 32'hffff_8001,
                "x8 = lh sign-extended halfword");
    expect_word(_dut._core._datapath._regfile._regs[9], 32'h0000_8001,
                "x9 = lhu zero-extended halfword");
    expect_word(_dut._core._datapath._regfile._regs[10], 32'h8001_7fff,
                "x10 = lw after byte/half stores");
    expect_word(_dut._dmem._memory[0], 32'h8001_7fff, "dmem[0] byte/half store result");
    expect_word(_dut._dmem._memory[1], 32'h8001_7fff, "dmem[1] copied by sw");

    if (errors == 0) begin
      $display("tb_core: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_core: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
