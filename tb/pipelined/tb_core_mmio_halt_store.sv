// tb_core_mmio_halt_store.sv - pipelined core regression for LUI -> store address.
//
//   make sim DESIGN=pipelined TB=core_mmio_halt_store
//   make wave DESIGN=pipelined TB=core_mmio_halt_store

`timescale 1ns / 1ps

module tb_core_mmio_halt_store
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;
  localparam string       ProgramFile   =
      "/home/josh/code/riscv-soc/tb/pipelined/tb_core_mmio_halt_store.mem";

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();
  irq_if _irq ();

  always_comb begin
  _irq.pending.platform = 16'h0000;
  _irq.pending.meip = 1'b0;
  _irq.pending.seip = 1'b0;
  _irq.pending.mtip = 1'b0;
  _irq.pending.stip = 1'b0;
  _irq.pending.msip = 1'b0;
  _irq.pending.ssip = 1'b0;
  _irq.pending.usip = 1'b0;
  end



  int unsigned       errors = 0;
  int unsigned       checks = 0;
  int unsigned       _stores_seen;
  word_t             _store_addr      [2];
  word_t             _store_data      [2];
  logic              _extra_store;
  /* verilator lint_off UNUSEDSIGNAL */
  logic              _observed_halted;
  logic        [3:0] _write_mask;
  /* verilator lint_on UNUSEDSIGNAL */

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .ibus(_ibus),
    .dbus(_dbus),
      .irq(_irq)
  );

  imem #(
    .DepthWords(16),
    .InitFile(ProgramFile)
  ) _imem (
    .clk(_clk),
    .rst(_rst),
    .ibus(_ibus)
  );

  assign _dbus.rsp.ready     = _dbus.req.valid;
  assign _dbus.rsp.read_data = '0;
  assign _observed_halted    = _halted;
  assign _write_mask         = _dbus.req.write_mask;

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _stores_seen   <= 0;
      _store_addr[0] <= '0;
      _store_addr[1] <= '0;
      _store_data[0] <= '0;
      _store_data[1] <= '0;
      _extra_store   <= 1'b0;
    end else if (_dbus.req.valid && _dbus.req.write_en) begin
      _stores_seen <= _stores_seen + 1;

      if (_stores_seen == 0) begin
        _store_addr[0] <= _dbus.req.addr;
        _store_data[0] <= _dbus.req.write_data;
      end else if (_stores_seen == 1) begin
        _store_addr[1] <= _dbus.req.addr;
        _store_data[1] <= _dbus.req.write_data;
      end else begin
        _extra_store <= 1'b1;
      end
    end
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_mmio_halt_store);
    end

    _rst = 1'b1;
    repeat (2) @(posedge _clk);

    @(negedge _clk);
    _rst = 1'b0;

    wait (_stores_seen == 2);
    repeat (2) @(posedge _clk);

    expect_word(_store_addr[0], 32'h1000_0000, "first store uses LED address");
    expect_word(_store_data[0], 32'h0000_00aa, "first store writes LED value");
    expect_word(_store_addr[1], 32'h1000_f000, "second store uses SIM_HALT address");
    expect_word(_store_data[1], 32'h0000_0000, "second store writes halt code");
    expect_word(_stores_seen, 2, "program performs exactly two stores before loop");
    expect_word(word_t'(_extra_store), '0, "program does not perform extra stores");

    if (errors == 0) begin
      $display("tb_core_mmio_halt_store: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_core_mmio_halt_store: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_mmio_halt_store: TIMEOUT after %0d cycles pc=0x%08h stores=%0d",
             TimeoutCycles, _pc, _stores_seen);
    $fatal(1);
  end

endmodule
