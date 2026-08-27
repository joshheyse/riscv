// tb_flow_control.sv - priority checks for pipeline flow redirects.
//
//   make sim DESIGN=pipelined TB=flow_control
//   make wave DESIGN=pipelined TB=flow_control

`timescale 1ns / 1ps

module tb_flow_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;

  redirect_t   _redirect;
  redirect_t   _mem_order_redirect;
  trap_stage_t _trap;
  logic        _mret_valid;
  logic        _sret_valid;
  epc_t        _mepc;
  epc_t        _sepc;
  flow_ctrl_t  _flow;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  flow_control _dut (
    .redirect(_redirect),
    .mem_order_redirect(_mem_order_redirect),
    .trap(_trap),
    .mret_valid(_mret_valid),
    .sret_valid(_sret_valid),
    .mepc(_mepc),
    .sepc(_sepc),
    .flow(_flow)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got %0b, expected %0b", what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, got, exp);
    end
  endtask

  task automatic expect_action(input flow_action_e got, input flow_action_e exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got %0d, expected %0d", what, got, exp);
    end
  endtask

  task automatic check(input string what, input flow_action_e exp_action,
                       input logic exp_redirect_valid, input pc_t exp_pc);
    #1;
    expect_action(_flow.action, exp_action, {what, " action"});
    expect_bit(_flow.redirect.valid, exp_redirect_valid, {what, " redirect valid"});
    expect_word(_flow.redirect.pc, exp_pc, {what, " redirect pc"});
  endtask

  initial begin
    _redirect = '0;
    _mem_order_redirect = '0;
    _trap = '0;
    _mret_valid = 1'b0;
    _sret_valid = 1'b0;
    _mepc = '0;
    _sepc = '0;

    check("idle", FLOW_ACTION_NONE, 1'b0, '0);

    _redirect = '{valid: 1'b1, pc: 32'h0000_0040};
    check("redirect", FLOW_ACTION_REDIRECT, 1'b1, 32'h0000_0040);

    _redirect = '0;
    _mret_valid = 1'b1;
    _mepc = 32'h0000_0080;
    check("mret", FLOW_ACTION_MRET, 1'b1, 32'h0000_0080);

    _redirect = '{valid: 1'b1, pc: 32'h0000_0040};
    check("mret beats redirect", FLOW_ACTION_MRET, 1'b1, 32'h0000_0080);

    _mret_valid = 1'b0;
    _sret_valid = 1'b1;
    _sepc = 32'h0000_00c0;
    check("sret beats redirect", FLOW_ACTION_SRET, 1'b1, 32'h0000_00c0);

    _trap.valid = 1'b1;
    _trap.payload = '{
        epc: 32'h0000_0004,
        cause: '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR},
        tval: 32'h0000_0000,
        handler_pc: 32'h0000_0100,
        target_priv: PRIV_MACHINE
    };
    check("trap beats xret and redirect", FLOW_ACTION_TRAP, 1'b1, 32'h0000_0100);

    if (_errors == 0) begin
      $display("tb_flow_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_flow_control: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $display("tb_flow_control: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_flow_control);
    end
  end

endmodule
