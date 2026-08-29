`timescale 1ns / 1ps

module tb_amo_alu
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100;

  amo_op_e       _op;
  integer_data_t _old_value;
  integer_data_t _operand;
  integer_data_t _new_value;
  int unsigned   _checks = 0;
  int unsigned   _errors = 0;

  amo_alu _dut (
    .op(_op),
    .old_value(_old_value),
    .operand(_operand),
    .new_value(_new_value)
  );

  task automatic check(input amo_op_e op, input integer_data_t old_value,
                       input integer_data_t operand, input integer_data_t expected,
                       input string what);
    _op = op;
    _old_value = old_value;
    _operand = operand;
    #1;
    _checks++;
    if (_new_value !== expected) begin
      _errors++;
      $error("%s: got 0x%08h, expected 0x%08h", what, _new_value, expected);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_amo_alu.vcd");
      $dumpvars(0, tb_amo_alu);
    end

    check(AMO_OP_ADD, 32'hffff_ffff, 32'h0000_0002, 32'h0000_0001, "add wraps");
    check(AMO_OP_SWAP, 32'h1234_5678, 32'hdead_beef, 32'hdead_beef, "swap");
    check(AMO_OP_XOR, 32'ha5a5_0f0f, 32'hffff_00ff, 32'h5a5a_0ff0, "xor");
    check(AMO_OP_AND, 32'ha5a5_0f0f, 32'hffff_00ff, 32'ha5a5_000f, "and");
    check(AMO_OP_OR, 32'ha5a5_0f0f, 32'h0000_f0f0, 32'ha5a5_ffff, "or");
    check(AMO_OP_MIN, 32'hffff_ffff, 32'h0000_0001, 32'hffff_ffff, "signed min");
    check(AMO_OP_MAX, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0001, "signed max");
    check(AMO_OP_MINU, 32'hffff_ffff, 32'h0000_0001, 32'h0000_0001, "unsigned min");
    check(AMO_OP_MAXU, 32'hffff_ffff, 32'h0000_0001, 32'hffff_ffff, "unsigned max");
    check(AMO_OP_MIN, 32'h8000_0000, 32'h7fff_ffff, 32'h8000_0000, "signed min boundary");
    check(AMO_OP_MAX, 32'h8000_0000, 32'h7fff_ffff, 32'h7fff_ffff, "signed max boundary");
    check(AMO_OP_MINU, 32'h8000_0000, 32'h7fff_ffff, 32'h7fff_ffff,
          "unsigned min boundary");
    check(AMO_OP_MAXU, 32'h8000_0000, 32'h7fff_ffff, 32'h8000_0000,
          "unsigned max boundary");
    check(AMO_OP_MIN, 32'h1234_5678, 32'h1234_5678, 32'h1234_5678,
          "signed min equality");
    check(AMO_OP_MAXU, 32'h89ab_cdef, 32'h89ab_cdef, 32'h89ab_cdef,
          "unsigned max equality");

    if (_errors == 0) begin
      $display("tb_amo_alu: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_amo_alu: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_amo_alu: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
