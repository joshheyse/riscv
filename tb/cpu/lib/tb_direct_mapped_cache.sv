`timescale 1ns / 1ps

module tb_direct_mapped_cache;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned BackingWords = 4096;

  logic  _clk;
  logic  _rst;
  int    _errors;
  int    _checks;
  int    _downstream_reads;
  int    _downstream_writes;
  string _phase;

  mem_if _upstream ();
  mem_if _downstream ();

  word_t                            _backing       [0:BackingWords-1];
  logic  [$clog2(BackingWords)-1:0] _backing_index;
  assign _backing_index = _downstream.req.addr[$clog2(BackingWords)+1:2];

  // Downstream grant gating.
  //
  // This cache never talks to `memory` directly -- `mem_arbiter` sits between
  // them. The arbiter forwards a request only while it is IDLE; after a grant
  // it spends at least a BUSY cycle and a DRAIN cycle ignoring `req.valid`
  // entirely and returning no `rsp.ready`. `_grant_gap` reproduces that: after
  // each accepted request the bus refuses the next `_grant_gap` cycles.
  //
  // So a master must hold `req.valid` until `rsp.ready`, the way `ifu` does.
  // One-cycle pulses are lost whenever they land in a refusal window. There is
  // deliberately no zero-gap pass: a bus that accepts every cycle would demand
  // the opposite convention, and no master can satisfy both while `mem_if`
  // lacks a request-accept signal distinct from `rsp.ready`.
  int unsigned _grant_gap;
  int unsigned _refuse_left;
  logic        _downstream_grant;

  assign _downstream_grant = _downstream.req.valid && (_refuse_left == 0);

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _refuse_left <= 0;
    end else if (_downstream_grant) begin
      _refuse_left <= _grant_gap;
    end else if (_refuse_left != 0) begin
      _refuse_left <= _refuse_left - 1;
    end
  end

  direct_mapped_cache _dut (
    .clk(_clk),
    .rst(_rst),
    .upstream(_upstream),
    .downstream(_downstream)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  // Registered-response backing memory behind that grant gate. The beat counts
  // asserted below are exact, so a master that re-issues an already-granted
  // request is caught as surplus downstream traffic.
  always_ff @(posedge _clk) begin
    if (_rst) begin
      _downstream.rsp <= '0;
      _downstream_reads <= 0;
      _downstream_writes <= 0;
    end else begin
      _downstream.rsp.ready <= _downstream_grant;
      if (_downstream_grant) begin
        _downstream.rsp.read_data <= _backing[_backing_index];
        if (_downstream.req.write_en) begin
          _downstream_writes <= _downstream_writes + 1;
          if (_downstream.req.write_mask[0])
            _backing[_backing_index][7:0] <= _downstream.req.write_data[7:0];
          if (_downstream.req.write_mask[1])
            _backing[_backing_index][15:8] <= _downstream.req.write_data[15:8];
          if (_downstream.req.write_mask[2])
            _backing[_backing_index][23:16] <= _downstream.req.write_data[23:16];
          if (_downstream.req.write_mask[3])
            _backing[_backing_index][31:24] <= _downstream.req.write_data[31:24];
        end else begin
          _downstream_reads <= _downstream_reads + 1;
        end
      end
    end
  end

  task automatic expect_word(input word_t actual, input word_t expected, input string what);
    _checks++;
    if (actual !== expected) begin
      $error("[%s] %s: expected 0x%08h, got 0x%08h", _phase, what, expected, actual);
      _errors++;
    end
  endtask

  task automatic expect_int(input int actual, input int expected, input string what);
    _checks++;
    if (actual != expected) begin
      $error("[%s] %s: expected %0d, got %0d", _phase, what, expected, actual);
      _errors++;
    end
  endtask

  task automatic seed_line(input word_t base_addr, input word_t seed);
    for (int unsigned beat = 0; beat < 8; beat++) begin
      _backing[(base_addr>>2)+beat] = seed + beat;
    end
  endtask

  task automatic cache_read(input word_t addr, output word_t data);
    @(negedge _clk);
    _upstream.req = '{valid: 1'b1, write_en: 1'b0, addr: addr, default: '0};
    while (!_upstream.rsp.ready) @(negedge _clk);
    data = _upstream.rsp.read_data;
    @(posedge _clk);
    #1;
    _upstream.req = '0;
  endtask

  task automatic cache_write(input word_t addr, input word_t data, input mem_write_mask_t mask);
    @(negedge _clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: addr,
        write_data: data,
        write_mask: mask
    };
    while (!_upstream.rsp.ready) @(negedge _clk);
    @(posedge _clk);
    #1;
    _upstream.req = '0;
  endtask

  // The full directed sequence, run against a minimally spaced bus and a
  // slower one. Behaviour and downstream beat counts must be identical under
  // both: bus back-pressure changes timing, never the traffic.
  task automatic run_sequence(input string label, input int unsigned grant_gap);
    localparam word_t LineA = 32'h0000_0020;
    localparam word_t LineB = 32'h0000_1020;
    localparam word_t LineC = 32'h0000_2020;
    word_t read_data;

    _phase = label;
    _grant_gap = grant_gap;

    _upstream.req = '0;
    _backing = '{default: '0};
    seed_line(LineA, 32'h1000_0000);
    seed_line(LineB, 32'h2000_0000);
    seed_line(LineC, 32'h3000_0000);

    _rst = 1'b1;
    repeat (2) @(posedge _clk);
    #1;
    _rst = 1'b0;

    cache_read(LineA + 32'd12, read_data);
    expect_word(read_data, 32'h1000_0003, "read miss returns requested refill word");
    expect_int(_downstream_reads, 8, "read miss issues eight refill beats");
    expect_int(_downstream_writes, 0, "clean miss has no write-back");

    for (int unsigned beat = 0; beat < 8; beat++) begin
      cache_read(LineA + word_t'(beat * 4), read_data);
      expect_word(read_data, 32'h1000_0000 + beat, "every refilled beat is installed");
    end
    expect_int(_downstream_reads, 8, "all words in a refilled line hit");

    cache_read(LineA + 32'd12, read_data);
    expect_word(read_data, 32'h1000_0003, "read hit returns cached word");
    expect_int(_downstream_reads, 8, "read hit avoids downstream memory");

    cache_write(LineA + 32'd12, 32'haaaa_bbbb, 4'b0011);
    cache_write(LineA + 32'd12, 32'hccdd_eeee, 4'b1100);
    cache_read(LineA + 32'd12, read_data);
    expect_word(read_data, 32'hccdd_bbbb, "masked write hit updates selected bytes");
    expect_int(_downstream_writes, 0, "write-back cache defers hit store");

    cache_read(LineB + 32'd4, read_data);
    expect_word(read_data, 32'h2000_0001, "conflicting miss returns new line");
    expect_int(_downstream_writes, 8, "dirty eviction writes eight beats");
    expect_int(_downstream_reads, 16, "conflicting miss refills eight beats");
    for (int unsigned beat = 0; beat < 8; beat++) begin
      expect_word(_backing[(LineA>>2)+beat], beat == 3 ? 32'hccdd_bbbb : 32'h1000_0000 + beat,
                  "dirty write-back preserves every line beat");
    end

    cache_read(LineA + 32'd12, read_data);
    expect_word(read_data, 32'hccdd_bbbb, "written-back line refills correctly");
    expect_int(_downstream_writes, 8, "clean eviction does not write back");
    expect_int(_downstream_reads, 24, "second clean refill uses eight beats");

    cache_write(LineC + 32'd8, 32'hdead_beef, 4'b1111);
    expect_int(_downstream_reads, 32, "write miss first refills the line");
    cache_read(LineC + 32'd8, read_data);
    expect_word(read_data, 32'hdead_beef, "write miss is applied before response");

    cache_read(LineB, read_data);
    expect_word(read_data, 32'h2000_0000, "dirty store-miss line can be evicted");
    expect_int(_downstream_writes, 16, "store-miss line writes back once");
    expect_word(_backing[(LineC+32'd8)>>2], 32'hdead_beef,
                "store-miss data reaches backing memory on eviction");

    _rst = 1'b1;
    @(posedge _clk);
    #1;
    _rst = 1'b0;
    cache_read(LineB, read_data);
    expect_word(read_data, 32'h2000_0000, "read after reset refills correct data");
    expect_int(_downstream_reads, 8, "reset invalidates previously cached lines");
    expect_int(_downstream_writes, 0, "reset clears dirty state");
  endtask

  initial begin
    _clk = 1'b0;
    _rst = 1'b1;
    _errors = 0;
    _checks = 0;
    _grant_gap = 2;
    _phase = "init";
    _upstream.req = '0;

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_direct_mapped_cache.vcd");
      $dumpvars(0, tb_direct_mapped_cache);
    end

    run_sequence("arbiter-paced bus", 2);
    run_sequence("slow bus", 5);

    if (_errors == 0) begin
      $display("tb_direct_mapped_cache: PASS (%0d checks)", _checks);
    end else begin
      $display("tb_direct_mapped_cache: FAIL (%0d errors)", _errors);
      $fatal(1);
    end
    $finish;
  end

  initial begin
    #200us;
    $fatal(1, "tb_direct_mapped_cache: watchdog timeout");
  end

endmodule
