`timescale 1ns / 1ps

module tb_div_execute
  import riscv_pkg::*;
();

  localparam int unsigned ClockPeriodNs = 10;
  localparam int unsigned TimeoutCycles = 100_000;
  localparam int unsigned RandomVectors = 2_000;
  localparam integer_data_t MinSigned = 32'h8000_0000;
  localparam integer_data_t NegOne = 32'hffff_ffff;

  logic        _clk;
  logic        _rst;
  logic        _cancel;
  div_req_t    _req;
  logic        _req_ready;
  div_rsp_t    _rsp;
  logic        _rsp_ready;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriodNs / 2) _clk = ~_clk;
  end

  div_execute _dut (
    .clk(_clk),
    .rst(_rst),
    .cancel(_cancel),
    .req(_req),
    .rsp_ready(_rsp_ready),
    .req_ready(_req_ready),
    .rsp(_rsp)
  );

  function automatic integer_data_t reference(input integer_data_t src_a,
                                              input integer_data_t src_b, input div_op_e op);
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

  task automatic check(input div_op_e op, input integer_data_t src_a, input integer_data_t src_b,
                       input string what);
    integer_data_t expected;

    expected = reference(src_a, src_b, op);

    @(negedge _clk);
    _req = '{valid: 1'b1, src_a: src_a, src_b: src_b, op: op};
    while (!_req_ready) begin
      @(negedge _clk);
    end
    @(posedge _clk);
    @(negedge _clk);
    _req.valid = 1'b0;

    while (!_rsp.valid) begin
      @(negedge _clk);
    end

    _checks++;
    if (_rsp.result !== expected) begin
      _errors++;
      $display("  FAIL %s: op=%s a=%08h b=%08h got=%08h expected=%08h", what, op.name(), src_a,
               src_b, _rsp.result, expected);
    end

    // The producer must hold both valid and result under response backpressure.
    @(negedge _clk);
    if (!_rsp.valid || (_rsp.result !== expected)) begin
      _errors++;
      $display("  FAIL %s: response changed while stalled", what);
    end

    _rsp_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _rsp_ready = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_div_execute.vcd");
      $dumpvars(0, tb_div_execute);
    end

    _rst = 1'b1;
    _cancel = 1'b0;
    _req = '0;
    _rsp_ready = 1'b0;
    repeat (3) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    check(DIV_OP_QUOTIENT_SIGNED, 32'd7, -32'd3, "signed quotient truncates toward zero");
    check(DIV_OP_REMAINDER_SIGNED, -32'd7, 32'd3, "signed remainder follows dividend");
    check(DIV_OP_QUOTIENT_UNSIGNED, 32'hffff_ffff, 32'd2, "unsigned quotient");
    check(DIV_OP_REMAINDER_UNSIGNED, 32'hffff_ffff, 32'd2, "unsigned remainder");

    for (int unsigned op = 0; op < 4; op++) begin
      check(div_op_e'(op), 32'h89ab_cdef, '0, "division by zero");
    end

    check(DIV_OP_QUOTIENT_SIGNED, MinSigned, NegOne, "signed quotient overflow");
    check(DIV_OP_REMAINDER_SIGNED, MinSigned, NegOne, "signed remainder overflow");
    check(DIV_OP_QUOTIENT_UNSIGNED, MinSigned, NegOne, "same bits are ordinary unsigned quotient");
    check(DIV_OP_REMAINDER_UNSIGNED, MinSigned, NegOne,
          "same bits are ordinary unsigned remainder");

    void'($urandom(32'h64_69_76_31));
    for (int unsigned i = 0; i < RandomVectors; i++) begin
      check(div_op_e'($urandom_range(0, 3)), 32'($urandom), 32'($urandom), "random");
    end

    if (_errors == 0) begin
      $display("tb_div_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_div_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_div_execute: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
