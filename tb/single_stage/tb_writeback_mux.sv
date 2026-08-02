// tb_writeback_mux.sv - self-checking testbench for writeback_mux.
//
//   make sim TB=writeback_mux

`timescale 1ns / 1ps

module tb_writeback_mux
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  result_src_t _result_src;
  word_t       _execute_result;
  word_t       _read_data;
  word_t       _writeback_data;

  int unsigned errors = 0;
  int unsigned checks = 0;

  writeback_mux _dut (
    .result_src(_result_src),
    .execute_result(_execute_result),
    .read_data(_read_data),
    .writeback_data(_writeback_data)
  );

  task automatic check(input result_src_t result_src, input word_t execute_result,
                       input word_t read_data, input word_t exp, input string what);
    _result_src     = result_src;
    _execute_result = execute_result;
    _read_data      = read_data;
    #1;
    checks++;
    if (_writeback_data !== exp) begin
      errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, _writeback_data, exp);
    end
  endtask

  initial begin
    check(RESULT_ALU, 32'h1111_2222, 32'haaaa_bbbb, 32'h1111_2222, "execute result");
    check(RESULT_MEM, 32'h1111_2222, 32'haaaa_bbbb, 32'haaaa_bbbb, "memory read data");

    if (errors == 0) begin
      $display("tb_writeback_mux: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_writeback_mux: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #TimeoutNs;
    $display("tb_writeback_mux: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
