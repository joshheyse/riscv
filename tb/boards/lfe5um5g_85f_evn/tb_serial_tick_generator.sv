`timescale 1ns / 1ps

module tb_serial_tick_generator;

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned ClocksPerTick = 4;
  localparam int unsigned TimeoutCycles = 100;

  logic _clk;
  logic _rst;
  logic _enable;
  logic _clear;
  logic _tick;
  logic _tick_every_cycle;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerTick)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .enable(_enable),
    .clear(_clear),
    .tick(_tick)
  );

  serial_tick_generator #(
    .ClocksPerTick(1)
  ) _dut_every_cycle (
    .clk(_clk),
    .rst(_rst),
    .enable(_enable),
    .clear(_clear),
    .tick(_tick_every_cycle)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic step_expect(input logic exp, input string what);
    @(posedge _clk);
    #1;
    expect_bit(_tick, exp, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_serial_tick_generator);
    end

    _rst    = 1'b1;
    _enable = 1'b0;
    _clear  = 1'b0;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_tick, 1'b0, "reset clears tick");
    expect_bit(_tick_every_cycle, 1'b0, "reset clears every-cycle tick");

    @(negedge _clk);
    _rst    = 1'b0;
    _enable = 1'b1;

    step_expect(1'b0, "enabled cycle 1 no tick");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator ticks on enabled cycle 1");
    step_expect(1'b0, "enabled cycle 2 no tick");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator ticks on enabled cycle 2");
    step_expect(1'b1, "enabled terminal-count cycle ticks");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator ticks on terminal-count cycle");
    step_expect(1'b0, "enabled cycle after tick no tick");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator ticks with normal generator");
    step_expect(1'b0, "tick is one cycle");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator continues ticking");
    step_expect(1'b0, "next period cycle 2 no tick");

    @(negedge _clk);
    _clear = 1'b1;
    step_expect(1'b0, "clear suppresses tick");
    expect_bit(_tick_every_cycle, 1'b0, "clear suppresses every-cycle tick");

    @(negedge _clk);
    _clear = 1'b0;
    step_expect(1'b0, "after clear cycle 1 no tick");
    step_expect(1'b0, "after clear cycle 2 no tick");
    step_expect(1'b1, "after clear terminal-count cycle ticks");
    step_expect(1'b0, "after clear cycle after tick no tick");

    @(negedge _clk);
    _enable = 1'b0;
    step_expect(1'b0, "disabled clears tick");
    expect_bit(_tick_every_cycle, 1'b0, "disabled clears every-cycle tick");
    step_expect(1'b0, "disabled holds tick low");
    expect_bit(_tick_every_cycle, 1'b0, "disabled holds every-cycle tick low");

    @(negedge _clk);
    _enable = 1'b1;
    step_expect(1'b0, "re-enabled cycle 1 no tick");
    expect_bit(_tick_every_cycle, 1'b1, "every-cycle generator ticks after re-enable");
    step_expect(1'b0, "re-enabled cycle 2 no tick");
    step_expect(1'b1, "re-enabled terminal-count cycle ticks");
    step_expect(1'b0, "re-enabled cycle after tick no tick");

    if (_errors == 0) begin
      $display("tb_serial_tick_generator: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_serial_tick_generator: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_serial_tick_generator: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
