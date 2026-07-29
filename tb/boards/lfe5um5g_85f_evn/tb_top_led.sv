`timescale 1ns / 1ps

module tb_top_led;
  localparam string ProgramFile =
      "/home/josh/code/riscv-soc/build/boards/lfe5um5g_85f_evn/apps/led_skip/led_skip.mem";

  logic       clk_12mhz;
  logic       rst_n;
  logic       uart_tx;
  logic [7:0] led_n;
  logic       unused_uart_tx;
  int         errors;

  assign unused_uart_tx = uart_tx;

  top #(
    .ImemInitFile      (ProgramFile),
    .PowerOnResetCycles(4)
  ) dut (
    .clk_12mhz(clk_12mhz),
    .rst_n    (rst_n),
    .uart_tx  (uart_tx),
    .led_n    (led_n)
  );

  initial begin
    clk_12mhz = 1'b0;
    forever #5 clk_12mhz = ~clk_12mhz;
  end

  initial begin
    errors = 0;
    rst_n  = 1'b1;

    repeat (12) @(posedge clk_12mhz);

    if (led_n !== 8'b1111_1110) begin
      $error("expected LED0 on after first MMIO store, got led_n=%b", led_n);
      errors++;
    end

    if (errors != 0) begin
      $fatal(1, "tb_top_led: FAIL (%0d errors)", errors);
    end

    $display("tb_top_led: PASS");
    $finish;
  end

  initial begin
    #1000;
    $fatal(1, "tb_top_led: watchdog timeout");
  end
endmodule
