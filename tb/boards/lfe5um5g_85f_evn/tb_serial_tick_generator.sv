`timescale 1ns / 1ps

module tb_serial_tick_generator;

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned ClocksPerTick = 4;
  localparam int unsigned TimeoutCycles = 100;

  logic clk;
  logic rst;
  logic enable;
  logic clear;
  logic tick;
  logic tick_every_cycle;

  int unsigned errors = 0;
  int unsigned checks = 0;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerTick)
  ) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .clear(clear),
    .tick(tick)
  );

  serial_tick_generator #(
    .ClocksPerTick(1)
  ) dut_every_cycle (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .clear(clear),
    .tick(tick_every_cycle)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic step_expect(input logic exp, input string what);
    @(posedge clk);
    #1;
    expect_bit(tick, exp, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_serial_tick_generator);
    end

    rst    = 1'b1;
    enable = 1'b0;
    clear  = 1'b0;

    repeat (2) @(posedge clk);
    #1;
    expect_bit(tick, 1'b0, "reset clears tick");
    expect_bit(tick_every_cycle, 1'b0, "reset clears every-cycle tick");

    @(negedge clk);
    rst    = 1'b0;
    enable = 1'b1;

    step_expect(1'b0, "enabled cycle 1 no tick");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator ticks on enabled cycle 1");
    step_expect(1'b0, "enabled cycle 2 no tick");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator ticks on enabled cycle 2");
    step_expect(1'b0, "enabled cycle 3 no tick");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator ticks on enabled cycle 3");
    step_expect(1'b1, "enabled cycle 4 ticks");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator ticks with normal generator");
    step_expect(1'b0, "tick is one cycle");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator continues ticking");
    step_expect(1'b0, "next period cycle 2 no tick");

    @(negedge clk);
    clear = 1'b1;
    step_expect(1'b0, "clear suppresses tick");
    expect_bit(tick_every_cycle, 1'b0, "clear suppresses every-cycle tick");

    @(negedge clk);
    clear = 1'b0;
    step_expect(1'b0, "after clear cycle 1 no tick");
    step_expect(1'b0, "after clear cycle 2 no tick");
    step_expect(1'b0, "after clear cycle 3 no tick");
    step_expect(1'b1, "after clear cycle 4 ticks");

    @(negedge clk);
    enable = 1'b0;
    step_expect(1'b0, "disabled clears tick");
    expect_bit(tick_every_cycle, 1'b0, "disabled clears every-cycle tick");
    step_expect(1'b0, "disabled holds tick low");
    expect_bit(tick_every_cycle, 1'b0, "disabled holds every-cycle tick low");

    @(negedge clk);
    enable = 1'b1;
    step_expect(1'b0, "re-enabled cycle 1 no tick");
    expect_bit(tick_every_cycle, 1'b1, "every-cycle generator ticks after re-enable");
    step_expect(1'b0, "re-enabled cycle 2 no tick");
    step_expect(1'b0, "re-enabled cycle 3 no tick");
    step_expect(1'b1, "re-enabled cycle 4 ticks");

    if (errors == 0) begin
      $display("tb_serial_tick_generator: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_serial_tick_generator: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_serial_tick_generator: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
