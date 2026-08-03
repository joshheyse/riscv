// tb_trap_controller.sv - self-checking testbench for trap_controller.
//
//   make sim  TB=trap_controller
//   make wave TB=trap_controller

`timescale 1ns / 1ps

module tb_trap_controller
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutTicks = 100;

  logic        _illegal_instr;
  instr_u      _instr;
  pc_t         _pc;
  mtvec_t      _mtvec;
  logic        _trap_valid;
  mepc_t       _trap_mepc;
  mcause_t     _trap_mcause;
  mtval_t      _trap_mtval;
  pc_t         _trap_pc;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  trap_controller _dut (
    .illegal_instr(_illegal_instr),
    .instr(_instr),
    .pc(_pc),
    .mtvec(_mtvec),
    .trap_valid(_trap_valid),
    .trap_mepc(_trap_mepc),
    .trap_mcause(_trap_mcause),
    .trap_mtval(_trap_mtval),
    .trap_pc(_trap_pc)
  );

  task automatic expect_bits(input logic [31:0] got, input logic [31:0] exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bool(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic drive(input logic illegal_instr, input instr_t instr, input pc_t pc,
                       input mtvec_t mtvec);
    _illegal_instr = illegal_instr;
    _instr.raw     = instr;
    _pc            = pc;
    _mtvec         = mtvec;
    #1;
  endtask

  task automatic expect_illegal_trap(input instr_t instr, input pc_t pc, input pc_t trap_pc,
                                     input string what);
    expect_bool(_trap_valid, 1'b1, {what, " valid"});
    expect_bits(_trap_mepc, pc, {what, " mepc"});
    expect_bits(_trap_mcause, 32'h0000_0002, {what, " mcause"});
    expect_bits(_trap_mtval, instr, {what, " mtval"});
    expect_bits(_trap_pc, trap_pc, {what, " trap_pc"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_trap_controller);
    end

    drive(1'b0, 32'h0000_0013, 32'h0000_0000, '{base: 30'h0000_0400, mode: MTVEC_MODE_DIRECT});
    expect_bool(_trap_valid, 1'b0, "legal instruction has no trap");

    drive(1'b1, 32'hffff_ffff, 32'h0000_0020, '{base: 30'h0000_0100, mode: MTVEC_MODE_DIRECT});
    expect_illegal_trap(32'hffff_ffff, 32'h0000_0020, 32'h0000_0400,
                        "illegal instruction direct mtvec");

    drive(1'b1, 32'h0000_0000, 32'h0000_0084, '{base: 30'h0000_0200, mode: MTVEC_MODE_VECTORED});
    expect_illegal_trap(32'h0000_0000, 32'h0000_0084, 32'h0000_0800,
                        "illegal instruction vectored mtvec");

    drive(1'b1, 32'h1234_5678, 32'h0000_00c0, '{base: 30'h0000_0000, mode: MTVEC_MODE_DIRECT});
    expect_illegal_trap(32'h1234_5678, 32'h0000_00c0, 32'h0000_0000,
                        "illegal instruction zero mtvec");

    if (_errors == 0) begin
      $display("tb_trap_controller: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_trap_controller: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutTicks);
    $display("tb_trap_controller: TIMEOUT after %0d ticks", TimeoutTicks);
    $fatal(1);
  end

endmodule
