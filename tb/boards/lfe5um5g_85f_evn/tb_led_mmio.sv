`timescale 1ns / 1ps

module tb_led_mmio
  import riscv_pkg::*;
();

  localparam realtime ClockPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;
  localparam word_t LedAddr = 32'h1000_0000;
  localparam int unsigned NumLeds = 8;

  logic clk;
  logic rst;
  logic mem_write;
  word_t mem_addr;
  word_t mem_write_data;
  logic selected;
  word_t read_data;
  logic [NumLeds-1:0] led;

  int unsigned errors = 0;
  int unsigned checks = 0;

  led_mmio #(
    .LedAddr(LedAddr),
    .NumLeds(NumLeds)
  ) dut (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected),
    .read_data(read_data),
    .led(led)
  );

  initial begin
    clk = 1'b0;
    forever #(ClockPeriod / 2) clk = ~clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_led(input logic [NumLeds-1:0] got, input logic [NumLeds-1:0] exp,
                            input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%02h, expected 0x%02h", $time, what, got, exp);
    end
  endtask

  task automatic tick;
    @(posedge clk);
    #1ps;
  endtask

  task automatic drive(input logic write, input word_t addr, input word_t data);
    mem_write      = write;
    mem_addr       = addr;
    mem_write_data = data;
    #1ps;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_led_mmio);
    end

    rst            = 1'b1;
    mem_write      = 1'b0;
    mem_addr       = '0;
    mem_write_data = '0;

    tick();
    expect_led(led, 8'h00, "reset clears LEDs");
    expect_word(read_data, 32'h0000_0000, "reset readback is zero");

    rst = 1'b0;
    drive(1'b0, LedAddr, 32'h0000_00ff);
    expect_bit(selected, 1'b1, "LED address selected");
    tick();
    expect_led(led, 8'h00, "read-only cycle does not update LEDs");

    drive(1'b1, LedAddr, 32'h0000_00a5);
    tick();
    expect_led(led, 8'ha5, "selected write updates LEDs");
    expect_word(read_data, 32'h0000_00a5, "readback reflects LED state");

    drive(1'b1, LedAddr + 32'h4, 32'h0000_005a);
    expect_bit(selected, 1'b0, "neighbor address not selected");
    tick();
    expect_led(led, 8'ha5, "unmapped write does not update LEDs");
    expect_word(read_data, 32'h0000_00a5, "unmapped readback still reflects LED state");

    drive(1'b1, LedAddr, 32'hffff_ff3c);
    tick();
    expect_led(led, 8'h3c, "write data truncates to LED width");
    expect_word(read_data, 32'h0000_003c, "truncated LED state is zero-extended on read");

    rst = 1'b1;
    drive(1'b1, LedAddr, 32'h0000_00ff);
    tick();
    expect_led(led, 8'h00, "reset wins over write");
    expect_word(read_data, 32'h0000_0000, "reset readback clears");

    if (errors == 0) begin
      $display("tb_led_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_led_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutCycles * ClockPeriod);
    $display("tb_led_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
