`timescale 1ns / 1ps

module tb_div_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;
  localparam int unsigned RandomVectors = 2_000;
  localparam integer_data_t MinSigned = 32'h8000_0000;
  localparam integer_data_t NegOne = 32'hffff_ffff;

  integer_data_t _src_a;
  integer_data_t _src_b;
  div_op_t       _div_op;
  integer_data_t _div_result;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  div_execute _dut (
    .src_a(_src_a),
    .src_b(_src_b),
    .div_op(_div_op),
    .div_result(_div_result)
  );

  function automatic integer_data_t reference(input integer_data_t src_a,
                                               input integer_data_t src_b,
                                               input div_op_t op);
    if (src_b == '0) begin
      case (op)
        DIV_OP_QUOTIENT_SIGNED, DIV_OP_QUOTIENT_UNSIGNED: return '1;
        default: return src_a;
      endcase
    end

    if (src_a == MinSigned && src_b == NegOne) begin
      case (op)
        DIV_OP_QUOTIENT_SIGNED:  return MinSigned;
        DIV_OP_REMAINDER_SIGNED: return '0;
        default: begin
        end
      endcase
    end

    case (op)
      DIV_OP_QUOTIENT_SIGNED:    return $signed(src_a) / $signed(src_b);
      DIV_OP_QUOTIENT_UNSIGNED:  return $unsigned(src_a) / $unsigned(src_b);
      DIV_OP_REMAINDER_SIGNED:   return $signed(src_a) % $signed(src_b);
      DIV_OP_REMAINDER_UNSIGNED: return $unsigned(src_a) % $unsigned(src_b);
      default:                   return '0;
    endcase
  endfunction

  task automatic check(input div_op_t op, input integer_data_t src_a,
                       input integer_data_t src_b, input string what);
    integer_data_t expected;

    _div_op = op;
    _src_a  = src_a;
    _src_b  = src_b;
    expected = reference(src_a, src_b, op);
    #1;
    _checks++;
    if (_div_result !== expected) begin
      _errors++;
      $display("  FAIL %s: op=%s a=%08h b=%08h got=%08h expected=%08h", what, op.name(),
               src_a, src_b, _div_result, expected);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_div_execute.vcd");
      $dumpvars(0, tb_div_execute);
    end

    check(DIV_OP_QUOTIENT_SIGNED, 32'd7, -32'd3, "signed quotient truncates toward zero");
    check(DIV_OP_REMAINDER_SIGNED, -32'd7, 32'd3, "signed remainder follows dividend");
    check(DIV_OP_QUOTIENT_UNSIGNED, 32'hffff_ffff, 32'd2, "unsigned quotient");
    check(DIV_OP_REMAINDER_UNSIGNED, 32'hffff_ffff, 32'd2, "unsigned remainder");

    for (int unsigned op = 0; op < 4; op++) begin
      check(div_op_t'(op), 32'h89ab_cdef, '0, "division by zero");
    end

    check(DIV_OP_QUOTIENT_SIGNED, MinSigned, NegOne, "signed quotient overflow");
    check(DIV_OP_REMAINDER_SIGNED, MinSigned, NegOne, "signed remainder overflow");
    check(DIV_OP_QUOTIENT_UNSIGNED, MinSigned, NegOne, "same bits are ordinary unsigned quotient");
    check(DIV_OP_REMAINDER_UNSIGNED, MinSigned, NegOne, "same bits are ordinary unsigned remainder");

    void'($urandom(32'h64_69_76_31));
    for (int unsigned i = 0; i < RandomVectors; i++) begin
      check(div_op_t'($urandom_range(0, 3)), 32'($urandom), 32'($urandom), "random");
    end

    if (_errors == 0) begin
      $display("tb_div_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_div_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_div_execute: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
