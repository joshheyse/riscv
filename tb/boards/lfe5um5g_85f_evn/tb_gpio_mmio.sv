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

  logic                          _clk;
  logic                          _rst;
  logic                          _mem_valid;
  logic                          _mem_write_en;
  word_t                         _mem_addr;
  word_t                         _mem_write_data;
  mem_write_mask_t               _mem_write_mask;
  logic                          _selected;
  logic                          _mem_ready;
  word_t                         _read_data;
  logic            [NumGpio-1:0] _gpio_in;
  logic            [NumGpio-1:0] _gpio_out;
  logic            [NumGpio-1:0] _gpio_oe;

  int unsigned                   errors = 0;
  int unsigned                   checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic                          _mem_ready_observed;
  /* verilator lint_on UNUSEDSIGNAL */
  assign _mem_ready_observed = _mem_ready;
  mem_if _mem ();

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;
  assign _mem_ready = _mem.rsp.ready;
  assign _read_data = _mem.rsp.read_data;

  gpio_mmio #(
    .GpioDataInAddr(DataInAddr),
    .GpioDataOutAddr(DataOutAddr),
    .GpioDirAddr(DirAddr),
    .GpioSetAddr(SetAddr),
    .GpioClearAddr(ClearAddr),
    .GpioToggleAddr(ToggleAddr),
    .NumGpio(NumGpio)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .selected(_selected),
    .gpio_in(_gpio_in),
    .gpio_out(_gpio_out),
    .gpio_oe(_gpio_oe)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
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
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_write_en = 1'b0;
    _mem_addr = addr;
    _mem_write_mask = '0;
    #1;
  endtask

  task automatic write_mmio(input word_t addr, input word_t data);
    @(negedge _clk);
    _mem_addr       = addr;
    _mem_write_data = data;
    _mem_write_mask = 4'b1111;
    _mem_valid      = 1'b1;
    _mem_write_en   = 1'b1;
    @(posedge _clk);
    #1;
    _mem_write_en   = 1'b0;
    _mem_write_mask = '0;
  endtask

  task automatic expect_selected_addr(input word_t addr, input string what);
    set_read_addr(addr);
    expect_bit(_selected, 1'b1, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_gpio_mmio);
    end

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _gpio_in        = 8'ha5;

    repeat (2) @(posedge _clk);
    #1;
    expect_byte(_gpio_out, 8'h00, "reset clears output latch");
    expect_byte(_gpio_oe, 8'h00, "reset clears output enable");

    @(negedge _clk);
    _rst = 1'b0;

    expect_selected_addr(DataInAddr, "DATA_IN address selected");
    expect_selected_addr(DataOutAddr, "DATA_OUT address selected");
    expect_selected_addr(DirAddr, "DIR address selected");
    expect_selected_addr(SetAddr, "SET address selected");
    expect_selected_addr(ClearAddr, "CLEAR address selected");
    expect_selected_addr(ToggleAddr, "TOGGLE address selected");

    set_read_addr(32'h2000_0000);
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_word(_read_data, 32'h0000_0000, "unmapped read returns zero");

    set_read_addr(DataInAddr);
    expect_word(_read_data, 32'h0000_00a5, "DATA_IN reads zero-extended GPIO input");

    write_mmio(DataInAddr, 32'h0000_00ff);
    expect_byte(_gpio_out, 8'h00, "DATA_IN write does not change output latch");
    expect_byte(_gpio_oe, 8'h00, "DATA_IN write does not change output enable");

    write_mmio(DataOutAddr, 32'hffff_0055);
    expect_byte(_gpio_out, 8'h55, "DATA_OUT write updates output latch");
    set_read_addr(DataOutAddr);
    expect_word(_read_data, 32'h0000_0055, "DATA_OUT read returns output latch");

    write_mmio(DirAddr, 32'hffff_00f0);
    expect_byte(_gpio_oe, 8'hf0, "DIR write updates output enable");
    set_read_addr(DirAddr);
    expect_word(_read_data, 32'h0000_00f0, "DIR read returns output enable");

    write_mmio(SetAddr, 32'h0000_000a);
    expect_byte(_gpio_out, 8'h5f, "SET write sets selected output bits");
    set_read_addr(SetAddr);
    expect_word(_read_data, 32'h0000_0000, "SET reads as zero");

    write_mmio(ClearAddr, 32'h0000_0015);
    expect_byte(_gpio_out, 8'h4a, "CLEAR write clears selected output bits");
    set_read_addr(ClearAddr);
    expect_word(_read_data, 32'h0000_0000, "CLEAR reads as zero");

    write_mmio(ToggleAddr, 32'h0000_00ff);
    expect_byte(_gpio_out, 8'hb5, "TOGGLE write flips selected output bits");
    set_read_addr(ToggleAddr);
    expect_word(_read_data, 32'h0000_0000, "TOGGLE reads as zero");

    _gpio_in = 8'h3c;
    set_read_addr(DataInAddr);
    expect_word(_read_data, 32'h0000_003c, "DATA_IN follows GPIO input");

    write_mmio(32'h2000_0000, 32'h0000_00ff);
    expect_byte(_gpio_out, 8'hb5, "unmapped write does not change output latch");
    expect_byte(_gpio_oe, 8'hf0, "unmapped write does not change output enable");

    if (errors == 0) begin
      $display("tb_gpio_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_gpio_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_gpio_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
