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
  trap_stage_t _trap;
  logic        _mret_valid;
  mepc_t       _mepc;
  flow_ctrl_t  _flow;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  flow_control _dut (
    .redirect(_redirect),
    .trap(_trap),
    .mret_valid(_mret_valid),
    .mepc(_mepc),
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

  task automatic check(input string what, input logic exp_redirect_valid, input pc_t exp_pc,
                       input logic exp_take_trap, input logic exp_flush_if_id,
                       input logic exp_flush_id_ex);
    #1;
    expect_bit(_flow.redirect.valid, exp_redirect_valid, {what, " redirect valid"});
    expect_word(_flow.redirect.pc, exp_pc, {what, " redirect pc"});
    expect_bit(_flow.take_trap, exp_take_trap, {what, " take trap"});
    expect_bit(_flow.flush_if_id, exp_flush_if_id, {what, " flush IF/ID"});
    expect_bit(_flow.flush_id_ex, exp_flush_id_ex, {what, " flush ID/EX"});
  endtask

  initial begin
    _redirect = '0;
    _trap = '0;
    _mret_valid = 1'b0;
    _mepc = '0;

    check("idle", 1'b0, '0, 1'b0, 1'b0, 1'b0);

    _redirect = '{valid: 1'b1, pc: 32'h0000_0040};
    check("redirect", 1'b1, 32'h0000_0040, 1'b0, 1'b1, 1'b1);

    _redirect = '0;
    _mret_valid = 1'b1;
    _mepc = 32'h0000_0080;
    check("mret", 1'b1, 32'h0000_0080, 1'b0, 1'b1, 1'b1);

    _redirect = '{valid: 1'b1, pc: 32'h0000_0040};
    check("mret beats redirect", 1'b1, 32'h0000_0080, 1'b0, 1'b1, 1'b1);

    _trap.valid = 1'b1;
    _trap.payload = '{
        mepc: 32'h0000_0004,
        mcause: '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR},
        mtval: 32'h0000_0000,
        pc: 32'h0000_0100
    };
    check("trap beats mret and redirect", 1'b1, 32'h0000_0100, 1'b1, 1'b1, 1'b1);

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
