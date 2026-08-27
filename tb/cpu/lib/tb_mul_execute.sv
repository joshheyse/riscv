`timescale 1ns / 1ps

module tb_mul_execute
  import riscv_pkg::*;
();

  localparam int unsigned ClockPeriodNs = 10;
  localparam int unsigned TimeoutCycles = 100_000;
  localparam int unsigned RandomVectors = 2_000;

  logic     _clk;
  logic     _rst;
  logic     _cancel;
  mul_req_t _req;
  logic     _req_ready;
  mul_rsp_t _rsp;
  logic     _rsp_ready;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriodNs / 2) _clk = ~_clk;
  end

  mul_execute _dut (
    .clk(_clk),
    .rst(_rst),
    .cancel(_cancel),
    .req(_req),
    .rsp_ready(_rsp_ready),
    .req_ready(_req_ready),
    .rsp(_rsp)
  );

  function automatic integer_data_t reference(input integer_data_t src_a,
                                               input integer_data_t src_b,
                                               input mul_op_e op);
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

  task automatic check(input mul_op_e op, input integer_data_t src_a,
                       input integer_data_t src_b, input string what);
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
      $display("  FAIL %s: op=%s a=%08h b=%08h got=%08h expected=%08h", what, op.name(),
               src_a, src_b, _rsp.result, expected);
    end

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
      $dumpfile("tb_mul_execute.vcd");
      $dumpvars(0, tb_mul_execute);
    end

    _rst = 1'b1;
    _cancel = 1'b0;
    _req = '0;
    _rsp_ready = 1'b0;
    repeat (3) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    check(MUL_OP_LOW, 32'hffff_ffff, 32'hffff_ffff, "low word ignores signedness");
    check(MUL_OP_HIGH_SS, 32'hffff_ffff, 32'h0000_0002, "signed negative times positive");
    check(MUL_OP_HIGH_SS, 32'h8000_0000, 32'hffff_ffff, "signed minimum times negative one");
    check(MUL_OP_HIGH_SU, 32'hffff_ffff, 32'hffff_ffff, "signed times maximum unsigned");
    check(MUL_OP_HIGH_UU, 32'hffff_ffff, 32'hffff_ffff, "maximum unsigned squared");
    check(MUL_OP_HIGH_UU, 32'h8000_0000, 32'h0000_0002, "unsigned high-bit operand");

    void'($urandom(32'h6d75_6c31));
    for (int unsigned i = 0; i < RandomVectors; i++) begin
      check(mul_op_e'($urandom_range(0, 3)), 32'($urandom), 32'($urandom), "random");
    end

    if (_errors == 0) begin
      $display("tb_mul_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_mul_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_mul_execute: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
