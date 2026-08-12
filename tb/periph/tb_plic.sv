`timescale 1ns / 1ps

module tb_plic
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 500;
  localparam int unsigned NumSources = 3;
  localparam mem_addr_t PlicBase = 32'h0c00_0000;
  localparam mem_addr_t PlicPendingAddr = 32'h0c00_1000;
  localparam mem_addr_t PlicMEnableAddr = 32'h0c00_2000;
  localparam mem_addr_t PlicMThresholdAddr = 32'h0c20_0000;
  localparam mem_addr_t PlicMClaimCompleteAddr = 32'h0c20_0004;

  logic                _clk;
  logic                _rst;
  logic                _selected;
  logic [NumSources:1] _source_request;
  mem_if _mem ();
  irq_if _sources[NumSources:1] ();
  irq_if _irq ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  plic #(
    .PlicBase(PlicBase),
    .PlicPriorityBaseAddr(PlicBase),
    .PlicPendingAddr(PlicPendingAddr),
    .PlicMEnableAddr(PlicMEnableAddr),
    .PlicMThresholdAddr(PlicMThresholdAddr),
    .PlicMClaimCompleteAddr(PlicMClaimCompleteAddr),
    .NumSources(NumSources),
    .PriorityBits(3)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .selected(_selected),
    .sources(_sources),
    .irq(_irq),
    .mem(_mem)
  );

  for (genvar id = 1; id <= NumSources; id++) begin : gen_source_drive
    assign _sources[id].pending.platform = '0;
    assign _sources[id].pending.meip = _source_request[id];
    assign _sources[id].pending.seip = 1'b0;
    assign _sources[id].pending.mtip = 1'b0;
    assign _sources[id].pending.stip = 1'b0;
    assign _sources[id].pending.msip = 1'b0;
    assign _sources[id].pending.ssip = 1'b0;
    assign _sources[id].pending.usip = 1'b0;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input mem_data_t got, input mem_data_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_irq(input logic exp_meip, input string what);
    _checks++;
    if (_irq.pending.meip !== exp_meip || _irq.pending.seip !== 1'b0 ||
        _irq.pending.mtip !== 1'b0 || _irq.pending.stip !== 1'b0 ||
        _irq.pending.msip !== 1'b0 || _irq.pending.ssip !== 1'b0 ||
        _irq.pending.usip !== 1'b0 || _irq.pending.platform !== 16'h0000) begin
      _errors++;
      $display("  FAIL [%0t] %s: irq pending=0x%06h, expected meip=%b only", $time, what,
               _irq.pending, exp_meip);
    end
  endtask

  task automatic drive_idle;
    _mem.req.valid      = 1'b0;
    _mem.req.write_en   = 1'b0;
    _mem.req.addr       = '0;
    _mem.req.write_data = '0;
    _mem.req.write_mask = '0;
  endtask

  task automatic mem_write(input mem_addr_t addr, input mem_data_t data, input string what);
    @(negedge _clk);
    _mem.req.valid      = 1'b1;
    _mem.req.write_en   = 1'b1;
    _mem.req.addr       = addr;
    _mem.req.write_data = data;
    _mem.req.write_mask = '1;
    #1;
    expect_bit(_selected, 1'b1, {what, " selected"});
    expect_bit(_mem.rsp.ready, 1'b1, {what, " ready"});
    @(posedge _clk);
    #1;
    drive_idle();
  endtask

  task automatic mem_read(input mem_addr_t addr, input mem_data_t exp, input logic exp_selected,
                          input string what);
    @(negedge _clk);
    _mem.req.valid      = 1'b1;
    _mem.req.write_en   = 1'b0;
    _mem.req.addr       = addr;
    _mem.req.write_data = '0;
    _mem.req.write_mask = '1;
    #1;
    expect_bit(_selected, exp_selected, {what, " selected"});
    expect_bit(_mem.rsp.ready, exp_selected, {what, " ready"});
    expect_word(_mem.rsp.read_data, exp, what);
    @(posedge _clk);
    #1;
    drive_idle();
  endtask

  task automatic claim(input mem_data_t exp_id, input string what);
    // The ID is sampled while the request is active, before the clock edge at
    // which the selected gateway records the claim.
    @(negedge _clk);
    _mem.req.valid      = 1'b1;
    _mem.req.write_en   = 1'b0;
    _mem.req.addr       = PlicMClaimCompleteAddr;
    _mem.req.write_data = '0;
    _mem.req.write_mask = '1;
    #1;
    expect_bit(_selected, 1'b1, {what, " selected"});
    expect_bit(_mem.rsp.ready, 1'b1, {what, " ready"});
    expect_word(_mem.rsp.read_data, exp_id, what);
    @(posedge _clk);
    #1;
    drive_idle();
  endtask

  task automatic set_request(input int unsigned id, input logic value);
    @(negedge _clk);
    _source_request[id] = value;
    @(posedge _clk);
    #1;
  endtask

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_plic);
    end

    _rst = 1'b1;
    drive_idle();
    _source_request = '0;

    repeat (2) @(posedge _clk);
    #1;
    expect_irq(1'b0, "reset has no output interrupt");
    mem_read(PlicBase + 32'd4, 32'h0000_0000, 1'b1, "source 1 priority reset");
    mem_read(PlicPendingAddr, 32'h0000_0000, 1'b1, "pending reset");
    mem_read(32'h0bff_fffc, 32'h0000_0000, 1'b0, "address below PLIC is unmapped");

    @(negedge _clk);
    _rst = 1'b0;

    mem_write(PlicBase + 32'd4, 32'd3, "set source 1 priority");
    mem_write(PlicBase + 32'd8, 32'd5, "set source 2 priority");
    mem_write(PlicBase + 32'd12, 32'd5, "set source 3 priority");
    mem_read(PlicBase + 32'd4, 32'd3, 1'b1, "source 1 priority readback");
    mem_read(PlicBase + 32'd8, 32'd5, 1'b1, "source 2 priority readback");
    mem_read(PlicBase + 32'd12, 32'd5, 1'b1, "source 3 priority readback");

    set_request(1, 1'b1);
    set_request(2, 1'b1);
    set_request(3, 1'b1);
    mem_read(PlicPendingAddr, 32'h0000_000e, 1'b1, "all raw requests become pending");
    expect_irq(1'b0, "pending but disabled sources do not interrupt");

    mem_write(PlicMEnableAddr, 32'h0000_000e, "enable all sources");
    mem_write(PlicMThresholdAddr, 32'd5, "threshold equals highest priority");
    expect_irq(1'b0, "priority equal to threshold is not eligible");
    mem_write(PlicMThresholdAddr, 32'd4, "lower threshold below highest priority");
    expect_irq(1'b1, "eligible source raises machine external interrupt");

    claim(32'd2, "equal-priority tie claims lower source ID 2");
    mem_read(PlicPendingAddr, 32'h0000_000a, 1'b1, "claim removes source 2 from pending");
    claim(32'd3, "next claim returns source 3");
    claim(32'd0, "source 1 remains below threshold so claim returns zero");
    expect_irq(1'b0, "no eligible source remains after claims");

    mem_write(PlicMThresholdAddr, 32'd2, "lower threshold to admit source 1");
    claim(32'd1, "lower threshold exposes source 1");
    mem_read(PlicPendingAddr, 32'h0000_0000, 1'b1, "all sources are claimed");

    set_request(1, 1'b0);
    set_request(2, 1'b0);
    set_request(3, 1'b0);
    mem_write(PlicMClaimCompleteAddr, 32'd6, "invalid completion ID is ignored");
    set_request(2, 1'b1);
    expect_irq(1'b0, "invalid ID 6 does not alias to claimed source 2");

    mem_write(PlicMClaimCompleteAddr, 32'd2, "complete source 2 while request is high");
    expect_irq(1'b1, "completion re-pends a still-requesting source");
    set_request(2, 1'b0);
    claim(32'd2, "re-pended source 2 can be claimed again");
    mem_write(PlicMClaimCompleteAddr, 32'd2, "complete source 2 with request low");
    mem_write(PlicMClaimCompleteAddr, 32'd1, "complete source 1");
    mem_write(PlicMClaimCompleteAddr, 32'd3, "complete source 3");
    expect_irq(1'b0, "completed sources return idle");

    if (_errors == 0) begin
      $display("tb_plic: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_plic: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_plic: watchdog timeout");
  end

endmodule
