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

  logic        _clk;
  logic        _rst;
  pc_src_t     _pc_src;
  logic        _pc_en;
  pc_t         _ieu_addr;
  pc_t         _pc;
  pc_t         _imem_addr;
  logic        _instr_valid;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  ifu _dut (
    .clk(_clk),
    .rst(_rst),
    .pc_src(_pc_src),
    .pc_en(_pc_en),
    .ieu_addr(_ieu_addr),
    .pc(_pc),
    .imem_addr(_imem_addr),
    .instr_valid(_instr_valid)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  // ------------------------------------------------------------- helpers --

  task automatic expect_fetch(input pc_t exp_pc, input pc_t exp_imem_addr, input logic exp_valid,
                              input string what);
    _checks++;
    if (_pc !== exp_pc || _imem_addr !== exp_imem_addr || _instr_valid !== exp_valid) begin
      _errors++;
      $display(
          "  FAIL [%0t] %s: pc=0x%08h imem_addr=0x%08h instr_valid=%b, expected pc=0x%08h imem_addr=0x%08h instr_valid=%b",
          $time, what, _pc, _imem_addr, _instr_valid, exp_pc, exp_imem_addr, exp_valid);
    end
  endtask

  task automatic tick(input string what, input pc_t exp_pc, input pc_t exp_imem_addr,
                      input logic exp_valid);
    @(posedge _clk);
    #1;
    expect_fetch(exp_pc, exp_imem_addr, exp_valid, what);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_ifu);
    end

    _rst      = 1'b1;
    _pc_src   = PC_SRC_INC;
    _pc_en    = 1'b1;
    _ieu_addr = 32'h1234_5678;

    tick("reset drives fetch state to zero", 32'h0000_0000, 32'h0000_0000, 1'b0);
    tick("reset holds fetch state at zero", 32'h0000_0000, 32'h0000_0000, 1'b0);

    @(negedge _clk);
    _rst = 1'b0;

    tick("first sequential fetch issues pc+4", 32'h0000_0000, 32'h0000_0004, 1'b1);
    tick("second sequential fetch issues pc+8", 32'h0000_0004, 32'h0000_0008, 1'b1);
    tick("third sequential fetch issues pc+12", 32'h0000_0008, 32'h0000_000c, 1'b1);

    @(negedge _clk);
    _pc_src   = PC_SRC_IEU_ADR;
    _ieu_addr = 32'h0000_0040;
    tick("target path issues ieu_addr", 32'h0000_000c, 32'h0000_0040, 1'b0);

    @(negedge _clk);
    _ieu_addr = 32'h0000_0080;
    tick("target path can issue a second target", 32'h0000_0040, 32'h0000_0080, 1'b0);

    @(negedge _clk);
    _pc_en    = 1'b0;
    _pc_src   = PC_SRC_INC;
    _ieu_addr = 32'h0000_0200;
    tick("disabled pc_en holds sequential state", 32'h0000_0040, 32'h0000_0080, 1'b0);

    @(negedge _clk);
    _pc_src = PC_SRC_IEU_ADR;
    tick("disabled pc_en holds target state", 32'h0000_0040, 32'h0000_0080, 1'b0);

    @(negedge _clk);
    _pc_en = 1'b1;
    tick("re-enabled pc_en issues target path", 32'h0000_0080, 32'h0000_0200, 1'b0);

    @(negedge _clk);
    _pc_src   = PC_SRC_INC;
    _ieu_addr = 32'hffff_fffc;
    tick("sequential path ignores ieu_addr", 32'h0000_0200, 32'h0000_0204, 1'b1);
    tick("sequential path continues from loaded target", 32'h0000_0204, 32'h0000_0208, 1'b1);

    @(negedge _clk);
    _rst      = 1'b1;
    _pc_src   = PC_SRC_IEU_ADR;
    _ieu_addr = 32'h0000_0200;
    tick("reset overrides target path", 32'h0000_0000, 32'h0000_0000, 1'b0);

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
