`timescale 1ns / 1ps

module tb_uart_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam int unsigned ClocksPerBit = 4;
  localparam word_t TxDataAddr = 32'h1000_1000;
  localparam word_t StatusAddr = 32'h1000_4000;

  logic clk;
  logic rst;
  logic mem_write;
  word_t mem_addr;
  word_t mem_write_data;
  logic selected;
  word_t read_data;
  logic tx;

  int unsigned errors = 0;
  int unsigned checks = 0;

  uart_mmio #(
    .ClocksPerBit(ClocksPerBit),
    .TxDataAddr  (TxDataAddr),
    .StatusAddr  (StatusAddr)
  ) dut (
    .clk(clk),
    .rst(rst),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .selected(selected),
    .read_data(read_data),
    .tx(tx)
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

  task automatic write_mmio(input word_t a, input word_t data);
    @(negedge clk);
    mem_addr       = a;
    mem_write_data = data;
    mem_write      = 1'b1;
    @(posedge clk);
    #1;
    mem_write = 1'b0;
  endtask

  task automatic expect_status_ready(input logic ready, input string what);
    @(negedge clk);
    mem_addr  = StatusAddr;
    mem_write = 1'b0;
    #1;
    expect_bit(selected, 1'b1, "status address selected");
    expect_word(read_data, {31'b0, ready}, what);
  endtask

  task automatic expect_tx_bit(input logic exp, input string what);
    repeat (ClocksPerBit / 2) @(posedge clk);
    #1;
    expect_bit(tx, exp, what);
    repeat (ClocksPerBit - (ClocksPerBit / 2)) @(posedge clk);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_uart_mmio);
    end

    rst            = 1'b1;
    mem_write      = 1'b0;
    mem_addr       = '0;
    mem_write_data = '0;

    repeat (2) @(posedge clk);
    #1;
    expect_bit(tx, 1'b1, "reset drives UART idle high");

    @(negedge clk);
    rst = 1'b0;
    expect_status_ready(1'b1, "idle status ready");

    write_mmio(TxDataAddr, 32'h0000_00a5);
    #1;
    expect_bit(selected, 1'b1, "tx data address selected");
    expect_word(read_data, 32'h0000_0000, "non-status read_data is zero");

    @(negedge clk);
    mem_addr = StatusAddr;
    #1;
    expect_word(read_data, 32'h0000_0000, "busy status not ready");

    // 0xa5 = 8'b1010_0101, transmitted LSB first:
    // start, 1, 0, 1, 0, 0, 1, 0, 1, stop.
    expect_tx_bit(1'b0, "start bit");
    expect_tx_bit(1'b1, "data bit 0");
    expect_tx_bit(1'b0, "data bit 1");
    expect_tx_bit(1'b1, "data bit 2");
    expect_tx_bit(1'b0, "data bit 3");
    expect_tx_bit(1'b0, "data bit 4");
    expect_tx_bit(1'b1, "data bit 5");
    expect_tx_bit(1'b0, "data bit 6");
    expect_tx_bit(1'b1, "data bit 7");
    expect_tx_bit(1'b1, "stop bit");

    repeat (1) @(posedge clk);
    expect_status_ready(1'b1, "ready after stop bit");
    expect_bit(tx, 1'b1, "idle high after frame");

    @(negedge clk);
    mem_addr = 32'h2000_0000;
    #1;
    expect_bit(selected, 1'b0, "unmapped address not selected");

    write_mmio(TxDataAddr, 32'h0000_003c);
    expect_tx_bit(1'b0, "second frame start");

    @(negedge clk);
    mem_addr       = TxDataAddr;
    mem_write_data = 32'h0000_00ff;
    mem_write      = 1'b1;
    @(posedge clk);
    #1;
    mem_write = 1'b0;

    expect_tx_bit(1'b0, "second frame data bit 0 ignores busy write");
    expect_tx_bit(1'b0, "second frame data bit 1 ignores busy write");
    expect_tx_bit(1'b1, "second frame data bit 2 ignores busy write");

    if (errors == 0) begin
      $display("tb_uart_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_uart_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_uart_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
