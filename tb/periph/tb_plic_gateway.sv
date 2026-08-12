`timescale 1ns / 1ps

module tb_plic_gateway;

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;

  logic        _clk;
  logic        _rst;
  logic        _request;
  logic        _claim;
  logic        _complete;
  logic        _pending;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  plic_gateway _dut (
    .clk(_clk),
    .rst(_rst),
    .request(_request),
    .claim(_claim),
    .complete(_complete),
    .pending(_pending)
  );

  task automatic expect_pending(input logic exp, input string what);
    _checks++;
    if (_pending !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: pending=%b, expected %b", $time, what, _pending, exp);
    end
  endtask

  task automatic step(input logic request, input logic claim, input logic complete,
                      input logic exp_pending, input string what);
    @(negedge _clk);
    _request  = request;
    _claim    = claim;
    _complete = complete;
    @(posedge _clk);
    #1;
    expect_pending(exp_pending, what);
  endtask

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_plic_gateway);
    end

    _rst      = 1'b1;
    _request  = 1'b0;
    _claim    = 1'b0;
    _complete = 1'b0;

    repeat (2) @(posedge _clk);
    #1;
    expect_pending(1'b0, "reset starts idle");

    @(negedge _clk);
    _rst = 1'b0;

    step(1'b0, 1'b1, 1'b1, 1'b0, "claim and complete are ignored while idle");
    step(1'b1, 1'b0, 1'b0, 1'b1, "request moves idle to pending");
    step(1'b0, 1'b0, 1'b1, 1'b1, "complete is ignored while pending");
    step(1'b0, 1'b1, 1'b0, 1'b0, "claim moves pending to claimed");
    step(1'b1, 1'b1, 1'b0, 1'b0, "request and claim do not re-pend while claimed");
    step(1'b1, 1'b0, 1'b1, 1'b1, "completion with request high re-pends source");
    step(1'b0, 1'b1, 1'b0, 1'b0, "re-pended source can be claimed again");
    step(1'b0, 1'b0, 1'b1, 1'b0, "completion with request low returns idle");
    step(1'b1, 1'b0, 1'b0, 1'b1, "idle gateway accepts a later request");

    _rst = 1'b1;
    @(posedge _clk);
    #1;
    expect_pending(1'b0, "reset clears a pending source");

    if (_errors == 0) begin
      $display("tb_plic_gateway: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_plic_gateway: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_plic_gateway: watchdog timeout");
  end

endmodule
