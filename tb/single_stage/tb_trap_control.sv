// tb_trap_control.sv - self-checking testbench for trap_control.
//
//   make sim  TB=trap_control
//   make wave TB=trap_control

`timescale 1ns / 1ps

module tb_trap_control
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutTicks = 100;

  trap_req_t   _trap_req;
  pc_t         _pc;
  mtvec_t      _mtvec;
  trap_stage_t _trap;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  trap_control _dut (
    .trap_req(_trap_req),
    .pc(_pc),
    .mtvec(_mtvec),
    .trap(_trap)
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

  task automatic drive(input logic trap_valid, input trap_src_t trap_src, input mtval_t mtval,
                       input pc_t pc, input mtvec_t mtvec);
    _trap_req = '{valid: trap_valid, src: trap_src, mtval: mtval};
    _pc       = pc;
    _mtvec    = mtvec;
    #1;
  endtask

  task automatic expect_illegal_trap(input instr_t instr, input pc_t pc, input pc_t trap_pc,
                                     input string what);
    expect_bool(_trap.valid, 1'b1, {what, " valid"});
    expect_bits(_trap.payload.mepc, pc, {what, " mepc"});
    expect_bits(_trap.payload.mcause, 32'h0000_0002, {what, " mcause"});
    expect_bits(_trap.payload.mtval, instr, {what, " mtval"});
    expect_bits(_trap.payload.pc, trap_pc, {what, " trap_pc"});
  endtask

  task automatic expect_trap(input word_t mcause, input word_t mtval, input pc_t pc,
                             input pc_t trap_pc, input string what);
    expect_bool(_trap.valid, 1'b1, {what, " valid"});
    expect_bits(_trap.payload.mepc, pc, {what, " mepc"});
    expect_bits(_trap.payload.mcause, mcause, {what, " mcause"});
    expect_bits(_trap.payload.mtval, mtval, {what, " mtval"});
    expect_bits(_trap.payload.pc, trap_pc, {what, " trap_pc"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_trap_control);
    end

    drive(1'b0, TRAP_SRC_NONE, 32'h0000_0000, 32'h0000_0000,
          '{base: 30'h0000_0400, mode: MTVEC_MODE_DIRECT});
    expect_bool(_trap.valid, 1'b0, "legal instruction has no trap");

    drive(1'b1, TRAP_SRC_ILLEGAL_INSTR, 32'hffff_ffff, 32'h0000_0020,
          '{base: 30'h0000_0100, mode: MTVEC_MODE_DIRECT});
    expect_illegal_trap(32'hffff_ffff, 32'h0000_0020, 32'h0000_0400,
                        "illegal instruction direct mtvec");

    drive(1'b1, TRAP_SRC_ILLEGAL_INSTR, 32'h0000_0000, 32'h0000_0084,
          '{base: 30'h0000_0200, mode: MTVEC_MODE_VECTORED});
    expect_illegal_trap(32'h0000_0000, 32'h0000_0084, 32'h0000_0800,
                        "illegal instruction vectored mtvec");

    drive(1'b1, TRAP_SRC_ILLEGAL_INSTR, 32'h1234_5678, 32'h0000_00c0,
          '{base: 30'h0000_0000, mode: MTVEC_MODE_DIRECT});
    expect_illegal_trap(32'h1234_5678, 32'h0000_00c0, 32'h0000_0000,
                        "illegal instruction zero mtvec");

    drive(1'b1, TRAP_SRC_ECALL, 32'h0000_0000, 32'h0000_0100,
          '{base: 30'h0000_0040, mode: MTVEC_MODE_DIRECT});
    expect_trap(32'h0000_000b, 32'h0000_0000, 32'h0000_0100, 32'h0000_0100,
                "ecall from machine mode");

    drive(1'b1, TRAP_SRC_EBREAK, 32'h0000_0000, 32'h0000_0104,
          '{base: 30'h0000_0044, mode: MTVEC_MODE_DIRECT});
    expect_trap(32'h0000_0003, 32'h0000_0000, 32'h0000_0104, 32'h0000_0110, "ebreak");

    drive(1'b1, TRAP_SRC_INSTR_ADDR_MISALIGNED, 32'h0000_0082, 32'h0000_0200,
          '{base: 30'h0000_0080, mode: MTVEC_MODE_DIRECT});
    expect_trap(32'h0000_0000, 32'h0000_0082, 32'h0000_0200, 32'h0000_0200,
                "instruction address misaligned");

    drive(1'b1, TRAP_SRC_LOAD_ADDR_MISALIGNED, 32'h0000_1002, 32'h0000_0204,
          '{base: 30'h0000_0080, mode: MTVEC_MODE_DIRECT});
    expect_trap(32'h0000_0004, 32'h0000_1002, 32'h0000_0204, 32'h0000_0200,
                "load address misaligned");

    drive(1'b1, TRAP_SRC_STORE_ADDR_MISALIGNED, 32'h0000_1002, 32'h0000_0208,
          '{base: 30'h0000_0080, mode: MTVEC_MODE_DIRECT});
    expect_trap(32'h0000_0006, 32'h0000_1002, 32'h0000_0208, 32'h0000_0200,
                "store address misaligned");

    if (_errors == 0) begin
      $display("tb_trap_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_trap_control: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutTicks);
    $display("tb_trap_control: TIMEOUT after %0d ticks", TimeoutTicks);
    $fatal(1);
  end

endmodule
