// tb_execute_result_mux.sv - self-checking testbench for execute_result_mux.
//
//   make sim TB=execute_result_mux

`timescale 1ns / 1ps

module tb_execute_result_mux
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  alu_result_src_t _alu_result_src;
  pc_t             _pc;
  word_t           _imm;
  word_t           _alu_result;
  word_t           _execute_result;

  int unsigned     errors = 0;
  int unsigned     checks = 0;

  execute_result_mux _dut (
    .alu_result_src(_alu_result_src),
    .pc(_pc),
    .imm(_imm),
    .alu_result(_alu_result),
    .execute_result(_execute_result)
  );

  task automatic check(input alu_result_src_t alu_result_src, input pc_t pc, input word_t imm,
                       input word_t alu_result, input word_t exp, input string what);
    _alu_result_src = alu_result_src;
    _pc             = pc;
    _imm            = imm;
    _alu_result     = alu_result;
    #1;
    checks++;
    if (_execute_result !== exp) begin
      errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, _execute_result, exp);
    end
  endtask

  initial begin
    check(ALU_RES_ALU, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h1111_2222, "ALU result");
    check(ALU_RES_PC_PLUS4, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h0000_1004,
          "PC plus 4");
    check(ALU_RES_IMM, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'haaaa_bbbb, "immediate");

    if (errors == 0) begin
      $display("tb_execute_result_mux: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_execute_result_mux: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #TimeoutNs;
    $display("tb_execute_result_mux: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
