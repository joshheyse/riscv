`timescale 1ns / 1ps

module tb_dip_switch_mmio
  import riscv_pkg::*;
();

  localparam realtime Step = 1ns;
  localparam int unsigned TimeoutSteps = 100;
  localparam word_t DipSwitchAddr = 32'h1000_3000;
  localparam int unsigned NumDipSwitches = 8;

  logic                                 _mem_valid;
  logic                                 _mem_write_en;
  word_t                                _mem_addr;
  word_t                                _mem_write_data;
  mem_write_mask_t                      _mem_write_mask;
  logic                                 _selected;
  logic                                 _mem_ready;
  word_t                                _read_data;
  logic            [NumDipSwitches-1:0] _dip_switch;
  mem_if _mem ();

  int unsigned errors = 0;
  int unsigned checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        _mem_ready_observed;
  /* verilator lint_on UNUSEDSIGNAL */
  assign _mem_ready_observed = _mem_ready;

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;
  assign _mem_ready = _mem.rsp.ready;
  assign _read_data = _mem.rsp.read_data;

  dip_switch_mmio #(
    .DipSwitchAddr(DipSwitchAddr),
    .NumDipSwitches(NumDipSwitches)
  ) _dut (
    .mem(_mem),
    .selected(_selected),
    .dip_switch(_dip_switch)
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
    _mem_addr   = addr;
    _dip_switch = switches;
    _mem_valid  = 1'b1;
    #Step;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_dip_switch_mmio);
    end

    _mem_write_en   = 1'b0;
    _mem_write_data = '0;
    _mem_write_mask = '0;

    set_inputs('0, '0);
    expect_bit(_selected, 1'b0, "reset-like unmapped address not selected");
    expect_word(_read_data, '0, "zero switches read as zero");

    set_inputs(DipSwitchAddr, 8'h00);
    expect_bit(_selected, 1'b1, "DIP switch address selected");
    expect_word(_read_data, 32'h0000_0000, "all switches off read zero");

    set_inputs(DipSwitchAddr, 8'ha5);
    expect_word(_read_data, 32'h0000_00a5, "switch pattern is zero-extended");

    set_inputs(DipSwitchAddr, 8'hff);
    expect_word(_read_data, 32'h0000_00ff, "all switches on are visible");

    set_inputs(DipSwitchAddr + 32'h4, 8'h3c);
    expect_bit(_selected, 1'b0, "neighbor address not selected");
    expect_word(_read_data, 32'h0000_003c, "read data still mirrors raw switch input");

    set_inputs(32'h2000_0000, 8'hc3);
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_word(_read_data, 32'h0000_00c3, "unmapped read data mirrors raw switch input");

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
