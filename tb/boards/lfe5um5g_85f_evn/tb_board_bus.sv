`timescale 1ns / 1ps

module tb_board_bus
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;

  logic clk;
  logic rst;
  logic [7:0] led;
  logic uart_tx;
  logic mem_write;
  word_t mem_addr;
  word_t mem_write_data;
  word_t mem_read_data;
  mem_size_t mem_size;
  logic mem_unsigned;

  int unsigned errors = 0;
  int unsigned checks = 0;

  board_bus #(
    .DmemDepthWords(16)
  ) dut (
    .clk(clk),
    .rst(rst),
    .led(led),
    .uart_tx(uart_tx),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_size(mem_size),
    .mem_unsigned(mem_unsigned)
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

  task automatic expect_byte(input logic [7:0] got, input logic [7:0] exp, input string what);
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
    mem_write = 1'b0;
    mem_addr  = addr;
    #1;
  endtask

  task automatic write_bus(input word_t addr, input word_t data);
    @(negedge clk);
    mem_addr       = addr;
    mem_write_data = data;
    mem_write      = 1'b1;
    @(posedge clk);
    #1;
    mem_write = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_board_bus);
    end

    rst            = 1'b1;
    mem_write      = 1'b0;
    mem_addr       = '0;
    mem_write_data = '0;
    mem_size       = MEM_SIZE_WORD;
    mem_unsigned   = 1'b0;

    repeat (2) @(posedge clk);
    #1;
    expect_byte(led, 8'h00, "reset clears LEDs");
    expect_bit(uart_tx, 1'b1, "reset leaves UART idle high");

    @(negedge clk);
    rst = 1'b0;

    set_read_addr(32'h2000_0000);
    expect_word(mem_read_data, '0, "unmapped read returns zero");

    write_bus(memmap_pkg::LedAddr, 32'h0000_00a5);
    expect_byte(led, 8'ha5, "LED write reaches LED MMIO");
    set_read_addr(memmap_pkg::LedAddr);
    expect_word(mem_read_data, 32'h0000_00a5, "LED read routes through board bus");

    write_bus(32'h2000_0000, 32'h0000_005a);
    expect_byte(led, 8'ha5, "unmapped write does not change LED MMIO");
    set_read_addr(32'h2000_0000);
    expect_word(mem_read_data, '0, "unmapped read still returns zero after write");

    write_bus(memmap_pkg::DmemBase + 32'h0000_0004, 32'hdead_beef);
    set_read_addr(memmap_pkg::DmemBase + 32'h0000_0004);
    expect_word(mem_read_data, 32'hdead_beef, "DMEM write/read routes to LSU");

    write_bus(memmap_pkg::LedAddr, 32'h0000_0011);
    set_read_addr(memmap_pkg::DmemBase + 32'h0000_0004);
    expect_word(mem_read_data, 32'hdead_beef, "LED write does not change DMEM");

    set_read_addr(memmap_pkg::UartStatusAddr);
    expect_word(mem_read_data, 32'h0000_0001, "UART status read routes ready bit");
    write_bus(memmap_pkg::UartTxAddr, 32'h0000_0055);
    set_read_addr(memmap_pkg::UartStatusAddr);
    expect_word(mem_read_data, 32'h0000_0000, "UART TX write makes UART busy");
    expect_byte(led, 8'h11, "UART write does not change LED MMIO");

    repeat (2) @(posedge clk);
    set_read_addr(memmap_pkg::TimerLoAddr);
    if (mem_read_data == '0) begin
      errors++;
      $display("  FAIL [%0t] timer low read: got zero after reset release", $time);
    end
    checks++;

    set_read_addr(memmap_pkg::TimerHiAddr);
    expect_word(mem_read_data, '0, "timer high read routes through board bus");

    if (errors == 0) begin
      $display("tb_board_bus: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_board_bus: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_board_bus: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
