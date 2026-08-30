// tb_pmp_decoder.sv - self-checking incremental PMP decoder testbench.
//
//   make sim TB=pmp_decoder
//   make wave TB=pmp_decoder

`timescale 1ns / 1ps

module tb_pmp_decoder
  import riscv_pkg::*;
  import pmp_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;

  logic               _clk;
  logic               _rst;
  pmp_state_t         _raw_state;
  csr_addr_raw_t      _write_addr;
  csr_data_t          _write_data;
  logic               _rebuild_start;
  logic               _rebuild_commit;
  pmp_region_state_t  _regions;
  pmp_state_t         _rebuild_candidate;
  logic               _rebuild_wait;
  logic               _rebuild_ready;
  pmp_state_t         _expected_candidate;
  pmp_region_state_t  _expected_regions;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  pmp_decoder _dut (
    .clk(_clk),
    .rst(_rst),
    .raw_state(_raw_state),
    .write_addr(_write_addr),
    .write_data(_write_data),
    .rebuild_start(_rebuild_start),
    .rebuild_commit(_rebuild_commit),
    .regions(_regions),
    .rebuild_candidate(_rebuild_candidate),
    .rebuild_wait(_rebuild_wait),
    .rebuild_ready(_rebuild_ready)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bool(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic expect_region(input int unsigned entry, input string what);
    _checks++;
    if (_regions.entries[entry] !== _expected_regions.entries[entry]) begin
      _errors++;
      $display("  FAIL [%0t] %s: entry %0d differs from expected decode", $time, what, entry);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_pmp_decoder);
    end

    _raw_state = '0;
    _raw_state.addr[0] = 32'h0000_0400;
    _raw_state.addr[1] = 32'h0000_0800;
    _raw_state.cfg[0] = 8'h1f;
    _raw_state.cfg[1] = 8'h8f;
    _write_addr = CSR_PMPADDR0;
    _write_data = 32'h0000_1000;
    _expected_candidate = pmp_state_after_write(_raw_state, _write_addr, _write_data);
    _expected_regions = pmp_decode_regions(_expected_candidate);
    _rebuild_start = 1'b0;
    _rebuild_commit = 1'b0;
    _rst = 1'b1;

    repeat (2) @(posedge _clk);
    #1;
    expect_bool(_rebuild_wait, 1'b0, "reset decoder idle");
    expect_bool(_rebuild_ready, 1'b0, "reset decoder not ready");
    _rst = 1'b0;

    // The start pulse captures the legalized candidate. The active table is
    // still untouched until the first build edge.
    _rebuild_start = 1'b1;
    #1;
    expect_bool(_rebuild_wait, 1'b1, "start asserts rebuild wait");
    @(posedge _clk);
    #1;
    _rebuild_start = 1'b0;
    expect_bool(_rebuild_wait, 1'b1, "build holds wait");
    expect_bool(_rebuild_candidate === _expected_candidate, 1'b1,
                "start captures legalized candidate");

    for (int unsigned entry = 0; entry < PmpNumEntries; entry++) begin
      @(posedge _clk);
      #1;
      if (entry < (PmpNumEntries - 1)) begin
        expect_bool(_rebuild_ready, 1'b0, "build is not ready early");
      end
      expect_region(entry, "directly rebuilds active entry");
    end

    expect_bool(_rebuild_wait, 1'b0, "ready releases rebuild wait");
    expect_bool(_rebuild_ready, 1'b1, "all entries decoded before ready");
    _rebuild_commit = 1'b1;
    @(posedge _clk);
    #1;
    _rebuild_commit = 1'b0;
    expect_bool(_rebuild_ready, 1'b0, "commit returns decoder to idle");
    expect_bool(_rebuild_wait, 1'b0, "idle keeps wait low");

    if (_errors == 0) begin
      $display("tb_pmp_decoder: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_pmp_decoder: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_pmp_decoder: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
