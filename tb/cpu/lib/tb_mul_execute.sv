`timescale 1ns / 1ps

module tb_mul_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;
  localparam int unsigned RandomVectors = 2_000;

  integer_data_t _src_a;
  integer_data_t _src_b;
  mul_op_t       _mul_op;
  integer_data_t _mul_result;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  mul_execute _dut (
    .src_a(_src_a),
    .src_b(_src_b),
    .mul_op(_mul_op),
    .mul_result(_mul_result)
  );

  function automatic integer_data_t reference(input integer_data_t src_a,
                                               input integer_data_t src_b,
                                               input mul_op_t op);
    logic signed [63:0] a;
    logic signed [63:0] b;
    logic signed [63:0] product;

    a = (op == MUL_OP_HIGH_SS || op == MUL_OP_HIGH_SU) ?
        $signed({{32{src_a[31]}}, src_a}) : $signed({32'b0, src_a});
    b = op == MUL_OP_HIGH_SS ? $signed({{32{src_b[31]}}, src_b}) :
                              $signed({32'b0, src_b});
    product = a * b;
    return op == MUL_OP_LOW ? product[31:0] : product[63:32];
  endfunction

  task automatic check(input mul_op_t op, input integer_data_t src_a,
                       input integer_data_t src_b, input string what);
    integer_data_t expected;

    _mul_op = op;
    _src_a  = src_a;
    _src_b  = src_b;
    expected = reference(src_a, src_b, op);
    #1;
    _checks++;
    if (_mul_result !== expected) begin
      _errors++;
      $display("  FAIL %s: op=%s a=%08h b=%08h got=%08h expected=%08h", what, op.name(),
               src_a, src_b, _mul_result, expected);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_mul_execute.vcd");
      $dumpvars(0, tb_mul_execute);
    end

    check(MUL_OP_LOW, 32'hffff_ffff, 32'hffff_ffff, "low word ignores signedness");
    check(MUL_OP_HIGH_SS, 32'hffff_ffff, 32'h0000_0002, "signed negative times positive");
    check(MUL_OP_HIGH_SS, 32'h8000_0000, 32'hffff_ffff, "signed minimum times negative one");
    check(MUL_OP_HIGH_SU, 32'hffff_ffff, 32'hffff_ffff, "signed times maximum unsigned");
    check(MUL_OP_HIGH_UU, 32'hffff_ffff, 32'hffff_ffff, "maximum unsigned squared");
    check(MUL_OP_HIGH_UU, 32'h8000_0000, 32'h0000_0002, "unsigned high-bit operand");

    void'($urandom(32'h6d75_6c31));
    for (int unsigned i = 0; i < RandomVectors; i++) begin
      check(mul_op_t'($urandom_range(0, 3)), 32'($urandom), 32'($urandom), "random");
    end

    if (_errors == 0) begin
      $display("tb_mul_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_mul_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_mul_execute: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
