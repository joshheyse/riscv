`timescale 1ns / 1ps

module tb_push_button_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 300;
  localparam int unsigned NumPushButtons = 4;
  localparam int unsigned DebounceCycles = 3;
  localparam word_t PushButtonAddr = 32'h1000_3010;
  localparam word_t IrqEnableAddr = 32'h1000_3014;
  localparam word_t IrqPendingAddr = 32'h1000_3018;

  logic                                 _clk;
  logic                                 _rst;
  logic                                 _mem_valid;
  logic                                 _mem_write_en;
  word_t                                _mem_addr;
  word_t                                _mem_write_data;
  mem_write_mask_t                      _mem_write_mask;
  logic                                 _selected;
  logic            [NumPushButtons-1:0] _push_button;
  mem_if _mem ();
  irq_if _irq ();

  int unsigned errors = 0;
  int unsigned checks = 0;

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;

  push_button_mmio #(
    .PushButtonAddr(PushButtonAddr),
    .IrqEnableAddr(IrqEnableAddr),
    .IrqPendingAddr(IrqPendingAddr),
    .NumPushButtons(NumPushButtons),
    .DebounceCycles(DebounceCycles)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .push_button(_push_button),
    .selected(_selected),
    .mem(_mem),
    .irq(_irq)
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

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic read_mmio(input word_t addr, input word_t expected, input string what);
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_write_en = 1'b0;
    _mem_addr = addr;
    #1;
    expect_bit(_selected, 1'b1, {what, " selected"});
    expect_bit(_mem.rsp.ready, 1'b1, {what, " ready"});
    expect_word(_mem.rsp.read_data, expected, what);
    @(negedge _clk);
    _mem_valid = 1'b0;
  endtask

  task automatic write_mmio(input word_t addr, input word_t data);
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_write_en = 1'b1;
    _mem_addr = addr;
    _mem_write_data = data;
    _mem_write_mask = '1;
    @(posedge _clk);
    #1;
    _mem_valid = 1'b0;
    _mem_write_en = 1'b0;
  endtask

  task automatic set_buttons(input logic [NumPushButtons-1:0] value);
    @(negedge _clk);
    _push_button = value;
  endtask

  task automatic wait_debounce;
    repeat (DebounceCycles + 3) @(posedge _clk);
    #1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_push_button_mmio);
    end

    _rst = 1'b1;
    _mem_valid = 1'b0;
    _mem_write_en = 1'b0;
    _mem_addr = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _push_button = '0;

    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    read_mmio(PushButtonAddr, 32'h0000_0000, "button state reset");
    read_mmio(IrqEnableAddr, 32'h0000_0000, "IRQ enable reset");
    read_mmio(IrqPendingAddr, 32'h0000_0000, "IRQ pending reset");
    expect_bit(_irq.pending.meip, 1'b0, "reset clears external interrupt");
    expect_bit(_irq.pending.msip, 1'b0, "push button never raises software interrupt");

    // A press is invisible until debounced, then records a sticky event.
    set_buttons(4'b0001);
    read_mmio(PushButtonAddr, 32'h0000_0000, "press hidden before debounce");
    wait_debounce();
    read_mmio(PushButtonAddr, 32'h0000_0001, "press visible after debounce");
    read_mmio(IrqPendingAddr, 32'h0000_0001, "disabled press becomes pending");
    expect_bit(_irq.pending.meip, 1'b0, "disabled pending press does not interrupt");

    write_mmio(IrqEnableAddr, 32'h0000_0005);
    read_mmio(IrqEnableAddr, 32'h0000_0005, "per-button IRQ enable mask");
    expect_bit(_irq.pending.meip, 1'b1, "enabling pending button raises interrupt");
    write_mmio(IrqPendingAddr, 32'h0000_0001);
    read_mmio(IrqPendingAddr, 32'h0000_0000, "W1C acknowledges press");
    expect_bit(_irq.pending.meip, 1'b0, "acknowledging press deasserts interrupt");

    // Releases update state but do not generate press interrupts.
    set_buttons(4'b0000);
    wait_debounce();
    read_mmio(PushButtonAddr, 32'h0000_0000, "release visible after debounce");
    read_mmio(IrqPendingAddr, 32'h0000_0000, "release does not become pending");

    // A pulse shorter than the debounce period affects neither state nor IRQ.
    set_buttons(4'b0010);
    @(posedge _clk);
    set_buttons(4'b0000);
    wait_debounce();
    read_mmio(PushButtonAddr, 32'h0000_0000, "short pulse is filtered");
    read_mmio(IrqPendingAddr, 32'h0000_0000, "short pulse does not become pending");

    // Pending and enable masks preserve the identity of the pressed button.
    set_buttons(4'b0100);
    wait_debounce();
    read_mmio(PushButtonAddr, 32'h0000_0004, "third button state");
    read_mmio(IrqPendingAddr, 32'h0000_0004, "third button pending bit");
    expect_bit(_irq.pending.meip, 1'b1, "enabled third button raises interrupt");
    write_mmio(IrqPendingAddr, 32'h0000_0004);
    expect_bit(_irq.pending.meip, 1'b0, "selective clear removes third-button interrupt");

    @(negedge _clk);
    _mem_addr  = 32'h2000_0000;
    _mem_valid = 1'b1;
    #1;
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_bit(_mem.rsp.ready, 1'b0, "unmapped request not acknowledged by peripheral");
    expect_word(_mem.rsp.read_data, '0, "unmapped read data is zero");

    if (errors == 0) begin
      $display("tb_push_button_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_push_button_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_push_button_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
