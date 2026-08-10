`timescale 1ns / 1ps

module tb_dip_switch_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;
  localparam int unsigned NumDipSwitches = 8;
  localparam word_t DipSwitchAddr = 32'h1000_3000;
  localparam word_t IrqEnableAddr = 32'h1000_3004;
  localparam word_t IrqPendingAddr = 32'h1000_3008;

  logic                                 _clk;
  logic                                 _rst;
  logic                                 _mem_valid;
  logic                                 _mem_write_en;
  word_t                                _mem_addr;
  word_t                                _mem_write_data;
  mem_write_mask_t                      _mem_write_mask;
  logic                                 _selected;
  logic            [NumDipSwitches-1:0] _dip_switch;
  mem_if _mem ();
  irq_if _irq ();

  int unsigned errors = 0;
  int unsigned checks = 0;

  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;

  dip_switch_mmio #(
    .DipSwitchAddr(DipSwitchAddr),
    .IrqEnableAddr(IrqEnableAddr),
    .IrqPendingAddr(IrqPendingAddr),
    .NumDipSwitches(NumDipSwitches)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .dip_switch(_dip_switch),
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

  task automatic change_switches(input logic [NumDipSwitches-1:0] value);
    @(negedge _clk);
    _dip_switch = value;
    repeat (3) @(posedge _clk);
    #1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_dip_switch_mmio);
    end

    _rst = 1'b1;
    _mem_valid = 1'b0;
    _mem_write_en = 1'b0;
    _mem_addr = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _dip_switch = '0;

    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    read_mmio(DipSwitchAddr, 32'h0000_0000, "switch state reset");
    read_mmio(IrqEnableAddr, 32'h0000_0000, "IRQ enable reset");
    read_mmio(IrqPendingAddr, 32'h0000_0000, "IRQ pending reset");
    expect_bit(_irq.pending.meip, 1'b0, "reset clears external interrupt");
    expect_bit(_irq.pending.msip, 1'b0, "DIP switch never raises software interrupt");

    // Changes remain pending even while their interrupt source is disabled.
    change_switches(8'h01);
    read_mmio(DipSwitchAddr, 32'h0000_0001, "synchronized switch state");
    read_mmio(IrqPendingAddr, 32'h0000_0001, "disabled change becomes pending");
    expect_bit(_irq.pending.meip, 1'b0, "disabled pending bit does not raise interrupt");

    write_mmio(IrqEnableAddr, 32'h0000_0005);
    read_mmio(IrqEnableAddr, 32'h0000_0005, "per-switch IRQ enable mask");
    expect_bit(_irq.pending.meip, 1'b1, "enabling pending switch raises interrupt");

    // Reading data does not acknowledge an event; pending is explicitly W1C.
    read_mmio(DipSwitchAddr, 32'h0000_0001, "data read leaves pending set");
    read_mmio(IrqPendingAddr, 32'h0000_0001, "pending survives data read");
    write_mmio(IrqPendingAddr, 32'h0000_0001);
    read_mmio(IrqPendingAddr, 32'h0000_0000, "write one clears pending bit");
    expect_bit(_irq.pending.meip, 1'b0, "clearing pending deasserts interrupt");

    // A disabled source still records its event and asserts once enabled.
    change_switches(8'h03);
    read_mmio(IrqPendingAddr, 32'h0000_0002, "second switch change is pending");
    expect_bit(_irq.pending.meip, 1'b0, "disabled second switch does not interrupt");
    write_mmio(IrqEnableAddr, 32'h0000_0007);
    expect_bit(_irq.pending.meip, 1'b1, "enabling second switch exposes pending event");
    write_mmio(IrqPendingAddr, 32'h0000_0002);
    expect_bit(_irq.pending.meip, 1'b0, "selective W1C clears enabled event");

    // Arrange a clear on the same cycle a synchronized transition is observed.
    @(negedge _clk);
    _dip_switch = 8'h07;
    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _mem_valid = 1'b1;
    _mem_write_en = 1'b1;
    _mem_addr = IrqPendingAddr;
    _mem_write_data = 32'h0000_0004;
    @(posedge _clk);
    #1;
    _mem_valid = 1'b0;
    _mem_write_en = 1'b0;
    read_mmio(IrqPendingAddr, 32'h0000_0004, "new event wins over simultaneous clear");

    @(negedge _clk);
    _mem_addr = 32'h2000_0000;
    _mem_valid = 1'b1;
    #1;
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_bit(_mem.rsp.ready, 1'b0, "unmapped request not acknowledged by peripheral");
    expect_word(_mem.rsp.read_data, '0, "unmapped read data is zero");

    if (errors == 0) begin
      $display("tb_dip_switch_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_dip_switch_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_dip_switch_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
