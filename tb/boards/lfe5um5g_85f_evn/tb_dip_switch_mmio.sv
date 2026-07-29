`timescale 1ns / 1ps

module tb_dip_switch_mmio
  import riscv_pkg::*;
();

  localparam realtime Step = 1ns;
  localparam int unsigned TimeoutSteps = 100;
  localparam word_t DipSwitchAddr = 32'h1000_3000;
  localparam int unsigned NumDipSwitches = 8;

  word_t mem_addr;
  logic selected;
  word_t read_data;
  logic [NumDipSwitches-1:0] dip_switch;

  int unsigned errors = 0;
  int unsigned checks = 0;

  dip_switch_mmio #(
    .DipSwitchAddr (DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) dut (
    .mem_addr  (mem_addr),
    .selected  (selected),
    .read_data (read_data),
    .dip_switch(dip_switch)
  );

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

  task automatic set_inputs(input word_t addr, input logic [NumDipSwitches-1:0] switches);
    mem_addr   = addr;
    dip_switch = switches;
    #Step;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_dip_switch_mmio);
    end

    set_inputs('0, '0);
    expect_bit(selected, 1'b0, "reset-like unmapped address not selected");
    expect_word(read_data, '0, "zero switches read as zero");

    set_inputs(DipSwitchAddr, 8'h00);
    expect_bit(selected, 1'b1, "DIP switch address selected");
    expect_word(read_data, 32'h0000_0000, "all switches off read zero");

    set_inputs(DipSwitchAddr, 8'ha5);
    expect_word(read_data, 32'h0000_00a5, "switch pattern is zero-extended");

    set_inputs(DipSwitchAddr, 8'hff);
    expect_word(read_data, 32'h0000_00ff, "all switches on are visible");

    set_inputs(DipSwitchAddr + 32'h4, 8'h3c);
    expect_bit(selected, 1'b0, "neighbor address not selected");
    expect_word(read_data, 32'h0000_003c, "read data still mirrors raw switch input");

    set_inputs(32'h2000_0000, 8'hc3);
    expect_bit(selected, 1'b0, "unmapped address not selected");
    expect_word(read_data, 32'h0000_00c3, "unmapped read data mirrors raw switch input");

    if (errors == 0) begin
      $display("tb_dip_switch_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_dip_switch_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutSteps * Step);
    $display("tb_dip_switch_mmio: TIMEOUT after %0d steps", TimeoutSteps);
    $fatal(1);
  end

endmodule
