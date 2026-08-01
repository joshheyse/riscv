`timescale 1ns / 1ps

module tb_gpio_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;
  localparam int unsigned NumGpio = 8;
  localparam word_t DataInAddr = 32'h1000_6000;
  localparam word_t DataOutAddr = 32'h1000_6004;
  localparam word_t DirAddr = 32'h1000_6008;
  localparam word_t SetAddr = 32'h1000_600c;
  localparam word_t ClearAddr = 32'h1000_6010;
  localparam word_t ToggleAddr = 32'h1000_6014;

  logic clk;
  logic rst;
  logic mem_write_en;
  word_t mem_addr;
  word_t mem_write_data;
  logic selected;
  word_t read_data;
  logic [NumGpio-1:0] gpio_in;
  logic [NumGpio-1:0] gpio_out;
  logic [NumGpio-1:0] gpio_oe;

  int unsigned errors = 0;
  int unsigned checks = 0;

  gpio_mmio #(
    .GpioDataInAddr (DataInAddr),
    .GpioDataOutAddr(DataOutAddr),
    .GpioDirAddr    (DirAddr),
    .GpioSetAddr    (SetAddr),
    .GpioClearAddr  (ClearAddr),
    .GpioToggleAddr (ToggleAddr),
    .NumGpio        (NumGpio)
  ) dut (
    .clk(clk),
    .rst(rst),
    .mem_write_en(mem_write_en),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected),
    .read_data(read_data),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .gpio_oe(gpio_oe)
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

  task automatic expect_byte(input logic [NumGpio-1:0] got, input logic [NumGpio-1:0] exp,
                             input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%02h, expected 0x%02h", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic set_read_addr(input word_t addr);
    @(negedge clk);
    mem_write_en = 1'b0;
    mem_addr = addr;
    #1;
  endtask

  task automatic write_mmio(input word_t addr, input word_t data);
    @(negedge clk);
    mem_addr       = addr;
    mem_write_data = data;
    mem_write_en   = 1'b1;
    @(posedge clk);
    #1;
    mem_write_en = 1'b0;
  endtask

  task automatic expect_selected_addr(input word_t addr, input string what);
    set_read_addr(addr);
    expect_bit(selected, 1'b1, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_gpio_mmio);
    end

    rst            = 1'b1;
    mem_write_en   = 1'b0;
    mem_addr       = '0;
    mem_write_data = '0;
    gpio_in        = 8'ha5;

    repeat (2) @(posedge clk);
    #1;
    expect_byte(gpio_out, 8'h00, "reset clears output latch");
    expect_byte(gpio_oe, 8'h00, "reset clears output enable");

    @(negedge clk);
    rst = 1'b0;

    expect_selected_addr(DataInAddr, "DATA_IN address selected");
    expect_selected_addr(DataOutAddr, "DATA_OUT address selected");
    expect_selected_addr(DirAddr, "DIR address selected");
    expect_selected_addr(SetAddr, "SET address selected");
    expect_selected_addr(ClearAddr, "CLEAR address selected");
    expect_selected_addr(ToggleAddr, "TOGGLE address selected");

    set_read_addr(32'h2000_0000);
    expect_bit(selected, 1'b0, "unmapped address not selected");
    expect_word(read_data, 32'h0000_0000, "unmapped read returns zero");

    set_read_addr(DataInAddr);
    expect_word(read_data, 32'h0000_00a5, "DATA_IN reads zero-extended GPIO input");

    write_mmio(DataInAddr, 32'h0000_00ff);
    expect_byte(gpio_out, 8'h00, "DATA_IN write does not change output latch");
    expect_byte(gpio_oe, 8'h00, "DATA_IN write does not change output enable");

    write_mmio(DataOutAddr, 32'hffff_0055);
    expect_byte(gpio_out, 8'h55, "DATA_OUT write updates output latch");
    set_read_addr(DataOutAddr);
    expect_word(read_data, 32'h0000_0055, "DATA_OUT read returns output latch");

    write_mmio(DirAddr, 32'hffff_00f0);
    expect_byte(gpio_oe, 8'hf0, "DIR write updates output enable");
    set_read_addr(DirAddr);
    expect_word(read_data, 32'h0000_00f0, "DIR read returns output enable");

    write_mmio(SetAddr, 32'h0000_000a);
    expect_byte(gpio_out, 8'h5f, "SET write sets selected output bits");
    set_read_addr(SetAddr);
    expect_word(read_data, 32'h0000_0000, "SET reads as zero");

    write_mmio(ClearAddr, 32'h0000_0015);
    expect_byte(gpio_out, 8'h4a, "CLEAR write clears selected output bits");
    set_read_addr(ClearAddr);
    expect_word(read_data, 32'h0000_0000, "CLEAR reads as zero");

    write_mmio(ToggleAddr, 32'h0000_00ff);
    expect_byte(gpio_out, 8'hb5, "TOGGLE write flips selected output bits");
    set_read_addr(ToggleAddr);
    expect_word(read_data, 32'h0000_0000, "TOGGLE reads as zero");

    gpio_in = 8'h3c;
    set_read_addr(DataInAddr);
    expect_word(read_data, 32'h0000_003c, "DATA_IN follows GPIO input");

    write_mmio(32'h2000_0000, 32'h0000_00ff);
    expect_byte(gpio_out, 8'hb5, "unmapped write does not change output latch");
    expect_byte(gpio_oe, 8'hf0, "unmapped write does not change output enable");

    if (errors == 0) begin
      $display("tb_gpio_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_gpio_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_gpio_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
