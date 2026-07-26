// tb_fpga_top.sv — Verilator testbench skeleton for fpga_top.
//
// Boilerplate only: clock, reset, waveform dump and a watchdog. No stimulus
// and no checking yet.
//
// Run with:  make sim DESIGN=single_stage   (or: just sim)

`timescale 1ns / 1ps

module tb_fpga_top;

  // Scale the DUT's clock down so simulation runs at a sane rate.
  localparam int unsigned ClkHz = 100_000_000;
  localparam realtime ClkPeriod = 10ns;

  // Give up after this many clocks so a hung test still terminates.
  localparam int unsigned TimeoutCycles = 10_000;

  localparam int unsigned NumLeds = 8;
  localparam int unsigned NumSwitches = 8;

  // TODO: drop the waiver once the testbench actually checks the DUT outputs.
  /* verilator lint_off UNUSEDSIGNAL */
  logic                   clk;
  logic                   rst_n;
  logic [NumSwitches-1:0] sw;
  logic [    NumLeds-1:0] led;
  logic                   uart_rx;
  logic                   uart_tx;
  /* verilator lint_on UNUSEDSIGNAL */

  fpga_top #(
      .ClkHz(ClkHz),
      .NumLeds(NumLeds),
      .NumSwitches(NumSwitches)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .sw(sw),
      .led(led),
      .uart_rx(uart_rx),
      .uart_tx(uart_tx)
  );

  // ---------------------------------------------------------------- clock --
  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // ---------------------------------------------------------------- reset --
  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // -------------------------------------------------------------- stimulus --
  initial begin
    sw = '0;
    uart_rx = 1'b1;  // UART idles high

    @(posedge rst_n);
    @(posedge clk);

    // TODO: drive stimulus and check results here.

    repeat (100) @(posedge clk);
    $display("[%0t] tb_fpga_top: done", $time);
    $finish;
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $error("[%0t] tb_fpga_top: timeout after %0d cycles", $time, TimeoutCycles);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_fpga_top);
    end
  end

endmodule
