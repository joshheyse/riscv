// tb_redirect_control.sv - directed checks for execute-stage redirects.
//
//   make sim DESIGN=pipelined TB=redirect_control
//   make wave DESIGN=pipelined TB=redirect_control

`timescale 1ns / 1ps

module tb_redirect_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  logic        _id_ex_valid;
  pc_src_t     _id_ex_pc_src;
  logic        _id_ex_clear_pc_lsb;
  word_t       _alu_result;
  redirect_t   _redirect;
  trap_req_t   _trap;

  int unsigned errors = 0;
  int unsigned checks = 0;

  redirect_control _dut (
    .id_ex_valid(_id_ex_valid),
    .id_ex_pc_src(_id_ex_pc_src),
    .id_ex_clear_pc_lsb(_id_ex_clear_pc_lsb),
    .alu_result(_alu_result),
    .redirect(_redirect),
    .trap(_trap)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic clear_inputs();
    _id_ex_valid = 1'b0;
    _id_ex_pc_src = PC_SRC_INC;
    _id_ex_clear_pc_lsb = 1'b0;
    _alu_result = '0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_redirect_control);
    end

    clear_inputs();
    _alu_result = 32'h0000_0040;
    #1;
    expect_bit(_redirect.valid, 1'b0, "invalid slot does not redirect");
    expect_word(_redirect.pc, 32'h0000_0040, "invalid slot still computes plain target");
    expect_bit(_trap.valid, 1'b0, "invalid slot does not trap");

    clear_inputs();
    _id_ex_valid  = 1'b1;
    _id_ex_pc_src = PC_SRC_INC;
    _alu_result   = 32'h0000_0044;
    #1;
    expect_bit(_redirect.valid, 1'b0, "sequential pc source does not redirect");
    expect_word(_redirect.pc, 32'h0000_0044, "sequential slot passes target bits through");
    expect_bit(_trap.valid, 1'b0, "sequential pc source does not trap");

    clear_inputs();
    _id_ex_valid  = 1'b1;
    _id_ex_pc_src = PC_SRC_IEU_ADR;
    _alu_result   = 32'h0000_0080;
    #1;
    expect_bit(_redirect.valid, 1'b1, "IEU address pc source redirects");
    expect_word(_redirect.pc, 32'h0000_0080, "redirect uses alu result");
    expect_bit(_trap.valid, 1'b0, "aligned redirect does not trap");

    clear_inputs();
    _id_ex_valid = 1'b1;
    _id_ex_pc_src = PC_SRC_IEU_ADR;
    _id_ex_clear_pc_lsb = 1'b1;
    _alu_result = 32'h0000_0025;
    #1;
    expect_bit(_redirect.valid, 1'b1, "jalr-style pc source redirects");
    expect_word(_redirect.pc, 32'h0000_0024, "jalr-style redirect clears low bit");
    expect_bit(_trap.valid, 1'b0, "jalr-style aligned target does not trap");

    clear_inputs();
    _id_ex_valid = 1'b1;
    _id_ex_pc_src = PC_SRC_IEU_ADR;
    _id_ex_clear_pc_lsb = 1'b1;
    _alu_result = 32'h0000_0023;
    #1;
    expect_bit(_redirect.valid, 1'b0, "jalr-style halfword target suppresses redirect");
    expect_bit(_trap.valid, 1'b1, "jalr-style halfword target traps");
    expect_word(_trap.mtval, 32'h0000_0022, "jalr-style trap reports cleared target");

    clear_inputs();
    _id_ex_valid  = 1'b1;
    _id_ex_pc_src = PC_SRC_IEU_ADR;
    _alu_result   = 32'h0000_0082;
    #1;
    expect_bit(_redirect.valid, 1'b0, "misaligned redirect is suppressed");
    expect_bit(_trap.valid, 1'b1, "misaligned redirect traps");
    expect_word(32'(_trap.src), 32'(TRAP_SRC_INSTR_ADDR_MISALIGNED),
                "misaligned redirect trap source");
    expect_word(_trap.mtval, 32'h0000_0082, "misaligned redirect trap reports target");

    if (errors == 0) begin
      $display("tb_redirect_control: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_redirect_control: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutSteps) #1;
    $display("tb_redirect_control: TIMEOUT after %0d steps", TimeoutSteps);
    $fatal(1);
  end

endmodule
