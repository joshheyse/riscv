// tb_core_mmio_halt_store.sv - pipelined core regression for LUI -> store address.
//
//   make sim DESIGN=pipelined TB=core_mmio_halt_store
//   make wave DESIGN=pipelined TB=core_mmio_halt_store

`timescale 1ns / 1ps

module tb_core_mmio_halt_store
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 600;
  localparam string       ProgramFile   =
      "/home/josh/code/riscv-soc/tb/cpu/pipelined/tb_core_mmio_halt_store.mem";

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  mem_if _mem (
    _clk,
    _rst
  );
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



  int unsigned       _errors = 0;
  int unsigned       _checks = 0;
  logic              _mmio_write;
  mem_addr_t         _mmio_write_addr;
  mem_data_t         _mmio_write_data;
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
    .time_value('0),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  tb_core_bus #(
    .Words(64),
    .InitFile(ProgramFile)
  ) _bus (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .mmio_wait(0),
    .mmio_read_data('0),
    .mmio_write(_mmio_write),
    .mmio_write_addr(_mmio_write_addr),
    .mmio_write_data(_mmio_write_data)
  );

  assign _observed_halted = _halted;
  assign _write_mask      = _dut._data_lsu_cache.req.write_mask;

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
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
    end else if (_mmio_write) begin
      _stores_seen <= _stores_seen + 1;

      if (_stores_seen == 0) begin
        _store_addr[0] <= _mmio_write_addr;
        _store_data[0] <= _mmio_write_data;
      end else if (_stores_seen == 1) begin
        _store_addr[1] <= _mmio_write_addr;
        _store_data[1] <= _mmio_write_data;
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

    if (_errors == 0) begin
      $display("tb_core_mmio_halt_store: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_mmio_halt_store: FAIL (%0d failures out of %0d checks)", _errors, _checks);
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
