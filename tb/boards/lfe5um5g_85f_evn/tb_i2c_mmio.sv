`timescale 1ns / 1ps

module tb_i2c_mmio
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned ClocksPerHalfBit = 3;
  localparam int unsigned WaitLimitCycles = 50;
  localparam int unsigned TimeoutCycles = 3_000;
  localparam word_t DataAddr = 32'h1000_5000;
  localparam word_t AddressAddr = 32'h1000_5004;
  localparam word_t ControlAddr = 32'h1000_5008;
  localparam word_t StatusAddr = 32'h1000_500c;
  localparam logic [6:0] I2cAddr = 7'h42;
  localparam logic [7:0] AddrByte = {I2cAddr, 1'b0};
  localparam logic [7:0] TxByte = 8'ha5;

  logic            _clk;
  logic            _rst;
  logic            _mem_valid;
  logic            _mem_write_en;
  word_t           _mem_addr;
  word_t           _mem_write_data;
  mem_write_mask_t _mem_write_mask;
  logic            _selected;
  logic            _mem_ready;
  word_t           _read_data;
  i2c_if _i2c ();

  int unsigned errors = 0;
  int unsigned checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        _mem_ready_observed;
  /* verilator lint_on UNUSEDSIGNAL */
  assign _mem_ready_observed = _mem_ready;
  mem_if _mem (
    _clk,
    _rst
  );

  // This testbench drives the master side and can always take a response.
  assign _mem.rsp_ready = 1'b1;


  assign _mem.req.valid = _mem_valid;
  assign _mem.req.write_en = _mem_write_en;
  assign _mem.req.addr = _mem_addr;
  assign _mem.req.write_data = _mem_write_data;
  assign _mem.req.write_mask = _mem_write_mask;
  assign _mem_ready = _mem.rsp.valid;
  assign _read_data = _mem.rsp.read_data;

  i2c_mmio #(
    .DataAddr(DataAddr),
    .ControlAddr(ControlAddr),
    .StatusAddr(StatusAddr),
    .AddressAddr(AddressAddr),
    .ClocksPerHalfBit(ClocksPerHalfBit)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .selected(_selected),
    .i2c(_i2c)
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

  task automatic expect_status(input logic busy, input logic ack_error, input string what);
    set_read_addr(StatusAddr);
    expect_bit(_selected, 1'b1, "status address selected");
    expect_word(_read_data, {30'b0, ack_error, busy}, what);
  endtask

  task automatic wait_until_scl_low(input string what);
    int unsigned waited = 0;
    while (_i2c.scl_drive_low !== 1'b1 && waited < WaitLimitCycles) begin
      @(posedge _clk);
      #1;
      waited++;
    end
    expect_bit(_i2c.scl_drive_low, 1'b1, what);
  endtask

  task automatic wait_until_scl_high(input string what);
    int unsigned waited = 0;
    while (_i2c.scl_drive_low !== 1'b0 && waited < WaitLimitCycles) begin
      @(posedge _clk);
      #1;
      waited++;
    end
    expect_bit(_i2c.scl_drive_low, 1'b0, what);
  endtask

  task automatic expect_i2c_bit(input logic exp, input string what);
    wait_until_scl_low({what, ": scl low phase observed"});
    expect_bit(_i2c.sda_drive_low, ~exp, {what, ": sda stable while scl low"});
    wait_until_scl_high({what, ": scl high phase observed"});
    expect_bit(_i2c.sda_drive_low, ~exp, {what, ": sda stable while scl high"});
    @(posedge _clk);
    #1;
  endtask

  task automatic drive_ack(input string what);
    wait_until_scl_low({what, ": ack low phase observed"});
    expect_bit(_i2c.sda_drive_low, 1'b0, {what, ": master releases sda for ack"});
    _i2c.sda_in = 1'b0;
    wait_until_scl_high({what, ": ack high phase observed"});
    expect_bit(_i2c.sda_drive_low, 1'b0, {what, ": master still releases sda for ack"});
    repeat (ClocksPerHalfBit) @(posedge _clk);
    #1;
    _i2c.sda_in = 1'b1;
  endtask

  task automatic expect_write_transaction(input logic ack_data);
    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      expect_i2c_bit(AddrByte[bit_idx], $sformatf("address bit %0d", bit_idx));
    end

    drive_ack("address ack");

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      expect_i2c_bit(TxByte[bit_idx], $sformatf("data bit %0d", bit_idx));
    end

    wait_until_scl_low("data ack: ack low phase observed");
    expect_bit(_i2c.sda_drive_low, 1'b0, "data ack: master releases sda");
    _i2c.sda_in = ack_data ? 1'b0 : 1'b1;
    wait_until_scl_high("data ack: ack high phase observed");
    repeat (ClocksPerHalfBit) @(posedge _clk);
    #1;
    _i2c.sda_in = 1'b1;

    wait_until_scl_high("stop keeps scl released");
    expect_bit(_i2c.sda_drive_low, 1'b1, "stop first phase drives sda low");
    repeat (ClocksPerHalfBit) @(posedge _clk);
    #1;
    expect_bit(_i2c.scl_drive_low, 1'b0, "stop second phase keeps scl released");
    expect_bit(_i2c.sda_drive_low, 1'b0, "stop second phase releases sda");
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_i2c_mmio);
    end

    _rst            = 1'b1;
    _mem_valid      = 1'b0;
    _mem_write_en   = 1'b0;
    _mem_addr       = '0;
    _mem_write_data = '0;
    _mem_write_mask = '0;
    _i2c.sda_in     = 1'b1;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_i2c.sda_drive_low, 1'b0, "reset releases sda");
    expect_bit(_i2c.scl_drive_low, 1'b0, "reset releases scl");
    expect_word(_read_data, 32'h0000_0000, "reset unmapped read is zero");

    @(negedge _clk);
    _rst = 1'b0;

    set_read_addr(AddressAddr);
    expect_bit(_selected, 1'b1, "address register selected");
    expect_word(_read_data, 32'h0000_0000, "initial address is zero");

    set_read_addr(DataAddr);
    expect_bit(_selected, 1'b1, "data register selected");
    expect_word(_read_data, 32'h0000_0000, "initial data read is zero");

    expect_status(1'b0, 1'b0, "initial status idle no error");

    write_mmio(AddressAddr, {25'h1ff_ffff, I2cAddr});
    set_read_addr(AddressAddr);
    expect_word(_read_data, {25'b0, I2cAddr}, "address write truncates to seven bits");

    write_mmio(DataAddr, {24'hff_ffff, TxByte});
    write_mmio(ControlAddr, 32'h0000_0001);
    #1;
    expect_bit(_i2c.scl_drive_low, 1'b0, "start keeps scl released");
    expect_bit(_i2c.sda_drive_low, 1'b1, "start drives sda low");

    expect_write_transaction(1'b1);

    repeat (ClocksPerHalfBit + 1) @(posedge _clk);
    #1;
    expect_status(1'b0, 1'b0, "idle after acknowledged transaction");

    write_mmio(ControlAddr, 32'h0000_0001);
    expect_write_transaction(1'b0);

    repeat (ClocksPerHalfBit + 1) @(posedge _clk);
    #1;
    expect_status(1'b0, 1'b1, "data nack latches ack_error");

    write_mmio(ControlAddr, 32'h0000_0001);
    #1;
    expect_status(1'b1, 1'b0, "new transaction clears ack_error");

    set_read_addr(32'h2000_0000);
    expect_bit(_selected, 1'b0, "unmapped address not selected");
    expect_word(_read_data, 32'h0000_0000, "unmapped read returns zero");

    if (errors == 0) begin
      $display("tb_i2c_mmio: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_i2c_mmio: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_i2c_mmio: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
