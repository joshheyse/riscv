// tb_system_access_control.sv - self-checking SYSTEM access policy tests.
//
//   make sim  TB=system_access_control
//   make wave TB=system_access_control

`timescale 1ns / 1ps

module tb_system_access_control
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  system_ctrl_t _system_ctrl;
  priv_mode_t   _priv_mode;
  logic         _illegal_system_access;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  system_access_control _dut (
    .system_ctrl(_system_ctrl),
    .priv_mode(_priv_mode),
    .illegal_system_access(_illegal_system_access)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic check(input logic en, input system_op_t op, input priv_mode_t priv_mode,
                       input logic exp_illegal, input string what);
    _system_ctrl = '{en: en, op: op};
    _priv_mode   = priv_mode;
    #1;
    expect_bit(_illegal_system_access, exp_illegal, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_system_access_control);
    end

    check(1'b0, SYSTEM_OP_MRET, PRIV_USER, 1'b0, "idle mret is legal");

    check(1'b1, SYSTEM_OP_MRET, PRIV_MACHINE, 1'b0, "machine mret is legal");
    check(1'b1, SYSTEM_OP_MRET, PRIV_SUPERVISOR, 1'b1, "supervisor mret is illegal");
    check(1'b1, SYSTEM_OP_MRET, PRIV_USER, 1'b1, "user mret is illegal");

    check(1'b1, SYSTEM_OP_ECALL, PRIV_USER, 1'b0, "ecall access is not checked here");
    check(1'b1, SYSTEM_OP_EBREAK, PRIV_USER, 1'b0, "ebreak access is not checked here");
    check(1'b1, SYSTEM_OP_WFI, PRIV_USER, 1'b0, "wfi access is not checked here");
    check(1'b1, SYSTEM_OP_ILLEGAL, PRIV_USER, 1'b0, "decode illegal is not checked here");

    if (_errors == 0) begin
      $display("tb_system_access_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_system_access_control: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutSteps);
    $display("tb_system_access_control: TIMEOUT");
    $fatal(1);
  end

endmodule
