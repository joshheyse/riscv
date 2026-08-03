// tb_execute_result_mux.sv - self-checking testbench for execute_result_mux.
//
//   make sim TB=execute_result_mux

`timescale 1ns / 1ps

module tb_execute_result_mux
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  execute_result_t _execute_result_kind;
  pc_t             _pc;
  word_t           _imm;
  word_t           _alu_result;
  word_t           _csr_result;
  word_t           _execute_result;

  int unsigned     errors = 0;
  int unsigned     checks = 0;

  execute_result_mux _dut (
    .execute_result_kind(_execute_result_kind),
    .pc(_pc),
    .imm(_imm),
    .alu_result(_alu_result),
    .csr_result(_csr_result),
    .execute_result(_execute_result)
  );

  task automatic check(input execute_result_t execute_result, input pc_t pc, input word_t imm,
                       input word_t alu_result, input word_t csr_result, input word_t exp,
                       input string what);
    _execute_result_kind = execute_result;
    _pc                  = pc;
    _imm                 = imm;
    _alu_result          = alu_result;
    _csr_result          = csr_result;
    #1;
    checks++;
    if (_execute_result !== exp) begin
      errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, _execute_result, exp);
    end
  endtask

  initial begin
    check(EXEC_RESULT_ALU, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h3333_4444, 32'h1111_2222,
          "ALU result");
    check(EXEC_RESULT_PC_PLUS4, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h3333_4444, 32'h0000_1004,
          "PC plus 4");
    check(EXEC_RESULT_IMM, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h3333_4444, 32'haaaa_bbbb,
          "immediate");
    check(EXEC_RESULT_CSR, 32'h0000_1000, 32'haaaa_bbbb, 32'h1111_2222, 32'h3333_4444, 32'h3333_4444,
          "CSR result");

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
