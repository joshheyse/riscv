`timescale 1ns / 1ps

module tb_push_button_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;
  localparam word_t PushButtonAddr = 32'h1000_3004;
  localparam int unsigned NumPushButtons = 1;
  localparam int unsigned DebounceCycles = 3;

  logic clk;
  logic rst;
  word_t mem_addr;
  logic selected;
  word_t read_data;
  logic [NumPushButtons-1:0] push_button;

  int unsigned errors = 0;
  int unsigned checks = 0;

  push_button_mmio #(
    .PushButtonAddr (PushButtonAddr),
    .NumPushButtons(NumPushButtons),
    .DebounceCycles(DebounceCycles)
  ) dut (
    .clk        (clk),
    .rst        (rst),
    .mem_addr   (mem_addr),
    .selected   (selected),
    .read_data  (read_data),
    .push_button(push_button)
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

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic set_addr(input word_t addr);
    @(negedge clk);
    mem_addr = addr;
    #1;
  endtask

  task automatic set_button(input logic [NumPushButtons-1:0] buttons);
    @(negedge clk);
    push_button = buttons;
    #1;
  endtask

  task automatic wait_debounce;
    repeat (DebounceCycles + 3) @(posedge clk);
    #1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_push_button_mmio);
    end

    rst         = 1'b1;
    mem_addr    = '0;
    push_button = '0;

    repeat (2) @(posedge clk);
    #1;
    expect_bit(selected, 1'b0, "reset unmapped address not selected");
    expect_word(read_data, '0, "reset released button reads zero");

    set_addr(PushButtonAddr);
    expect_bit(selected, 1'b1, "push-button address selected");
    expect_word(read_data, 32'h0000_0000, "reset mapped read is zero");

    @(negedge clk);
    rst = 1'b0;
    #1;

    set_button(1'b1);
    expect_word(read_data, 32'h0000_0000, "press is not visible before debounce");
    wait_debounce();
    expect_word(read_data, 32'h0000_0001, "pressed button is visible after debounce");

    set_button(1'b0);
    expect_word(read_data, 32'h0000_0001, "release is not visible before debounce");
    wait_debounce();
    expect_word(read_data, 32'h0000_0000, "released button is visible after debounce");

    set_button(1'b1);
    @(posedge clk);
    set_button(1'b0);
    wait_debounce();
    expect_word(read_data, 32'h0000_0000, "short pulse is filtered by debounce");

    set_button(1'b1);
    wait_debounce();
    set_addr(PushButtonAddr + 32'h4);
    expect_bit(selected, 1'b0, "neighbor address not selected");
    expect_word(read_data, 32'h0000_0001, "read data still mirrors raw button input");

    set_addr(32'h2000_0000);
    expect_bit(selected, 1'b0, "unmapped address not selected");
    expect_word(read_data, 32'h0000_0001, "unmapped read data still mirrors debounced button");

    if (errors == 0) begin
      $display("tb_push_button_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_push_button_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_push_button_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
