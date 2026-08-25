`timescale 1ns / 1ps

module tb_set_associative_cache;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned BackingWords = 8192;

  logic  _clk;
  logic  _rst;
  int    _errors;
  int    _checks;
  int    _downstream_reads;
  int    _downstream_writes;
  string _phase;

  mem_if _upstream (
      _clk,
      _rst
  );
  mem_if _downstream (
      _clk,
      _rst
  );
  cache_command_if _cache_command ();

  logic _upstream_rsp_ready;
  logic _command_valid;
  cache_command_op_t _command_op;
  logic _command_done_ready;
  assign _upstream.rsp_ready = _upstream_rsp_ready;
  assign _cache_command.valid = _command_valid;
  assign _cache_command.op = _command_op;
  assign _cache_command.done_ready = _command_done_ready;


  word_t                            _backing       [0:BackingWords-1];
  logic  [$clog2(BackingWords)-1:0] _backing_index;
  assign _backing_index = _downstream.req.addr[$clog2(BackingWords)+1:2];

  // Downstream refusal.
  //
  // This cache never talks to `memory` directly -- `mem_arbiter` sits between
  // them, and it only forwards a request while it is idle. That refusal is
  // expressed on `req_ready`: after each accepted request the model withholds
  // acceptance for `_grant_gap` cycles. Nothing is lost while it refuses, so a
  // master simply keeps the beat presented until it is taken.
  int unsigned _grant_gap;
  int unsigned _refuse_left;
  logic        _downstream_grant;

  assign _downstream.req_ready = (_refuse_left == 0);
  assign _downstream_grant = _downstream.req.valid && _downstream.req_ready;

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _refuse_left <= 0;
    end else if (_downstream_grant) begin
      _refuse_left <= _grant_gap;
    end else if (_refuse_left != 0) begin
      _refuse_left <= _refuse_left - 1;
    end
  end

  set_associative_cache _dut (
      .clk(_clk),
      .rst(_rst),
      .upstream(_upstream),
      .downstream(_downstream),
      .cache_command(_cache_command)
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
      _downstream.rsp.valid <= _downstream_grant;
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

  task automatic expect_bit(input logic actual, input logic expected, input string what);
    _checks++;
    if (actual !== expected) begin
      $error("[%s] %s: expected %0b, got %0b", _phase, what, expected, actual);
      _errors++;
    end
  endtask

  task automatic seed_line(input word_t base_addr, input word_t seed);
    for (int unsigned beat = 0; beat < 8; beat++) begin
      _backing[(base_addr>>2)+beat] = seed + beat;
    end
  endtask

  // Hold the request until the cache accepts it, then take it off the bus and
  // wait for the response. The cache may answer during acceptance or later.
  task automatic cache_access(input word_t addr, input logic write_en, input word_t data_in,
                              input mem_write_mask_t mask, output word_t data_out);
    logic answered_on_accept;

    @(negedge _clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: write_en,
        addr: addr,
        write_data: data_in,
        write_mask: mask
    };
    #1;
    while (!_upstream.req_ready) @(negedge _clk);
    answered_on_accept = _upstream.rsp.valid;
    data_out = _upstream.rsp.read_data;

    @(posedge _clk);
    #1;
    _upstream.req = '0;

    if (!answered_on_accept) begin
      while (!_upstream.rsp.valid) @(negedge _clk);
      data_out = _upstream.rsp.read_data;
      @(posedge _clk);
      #1;
    end
  endtask

  task automatic cache_read(input word_t addr, output word_t data);
    cache_access(addr, 1'b0, '0, '0, data);
  endtask

  task automatic cache_write(input word_t addr, input word_t data, input mem_write_mask_t mask);
    /* verilator lint_off UNUSEDSIGNAL */
    word_t discarded;
    /* verilator lint_on UNUSEDSIGNAL */
    cache_access(addr, 1'b1, data, mask, discarded);
  endtask

  task automatic issue_command(input cache_command_op_t op, input int unsigned response_stall = 0);
    @(negedge _clk);
    _command_valid = 1'b1;
    _command_op = op;
    while (!_cache_command.ready) begin
      @(negedge _clk);
    end
    @(posedge _clk);
    #1;
    _command_valid = 1'b0;
    _command_op = '0;

    while (!_cache_command.done_valid) begin
      @(negedge _clk);
    end
    _command_done_ready = 1'b0;
    repeat (response_stall) begin
      expect_bit(_cache_command.done_valid, 1'b1,
                 "maintenance completion remains valid under back-pressure");
      @(negedge _clk);
    end
    _command_done_ready = 1'b1;
    @(posedge _clk);
    #1;
    expect_bit(_cache_command.done_valid, 1'b0, "maintenance completion transfers once");
  endtask

  task automatic run_maintenance_sequence();
    localparam word_t LineA = 32'h0000_0020;
    localparam word_t LineB = 32'h0000_1020;
    word_t read_data;
    int reads_before;
    int writes_before;

    _phase = "maintenance";
    _grant_gap = 2;
    _upstream.req = '0;
    _backing = '{default: '0};
    seed_line(LineA, 32'h1000_0000);
    seed_line(LineB, 32'h2000_0000);

    _rst = 1'b1;
    repeat (2) begin
      @(posedge _clk);
    end
    #1;
    _rst = 1'b0;

    cache_read(LineA, read_data);
    reads_before = _downstream_reads;
    issue_command('{clean: 1'b0, invalidate: 1'b1}, 3);
    expect_int(_downstream_writes, 0, "invalidate does not write a clean line");
    cache_read(LineA, read_data);
    expect_int(_downstream_reads, reads_before + 8, "invalidate forces a refill");

    cache_write(LineA + 32'd4, 32'hdead_beef, 4'b1111);
    reads_before  = _downstream_reads;
    writes_before = _downstream_writes;
    issue_command('{clean: 1'b1, invalidate: 1'b0});
    expect_int(_downstream_writes, writes_before + 8, "clean writes one dirty line");
    expect_word(_backing[(LineA+32'd4)>>2], 32'hdead_beef, "clean updates backing memory");
    cache_read(LineA + 32'd4, read_data);
    expect_word(read_data, 32'hdead_beef, "clean retains cached data");
    expect_int(_downstream_reads, reads_before, "clean retains line validity");
    cache_read(LineB, read_data);
    expect_int(_downstream_writes, writes_before + 8, "cleaned line is not written back again");

    // Both conflicting lines are resident in separate ways. Dirty both so a
    // clean+invalidate command must visit and write back both ways of the set.
    cache_write(LineA + 32'd4, 32'haaaa_aaaa, 4'b1111);
    cache_write(LineB + 32'd8, 32'hbbbb_bbbb, 4'b1111);
    reads_before  = _downstream_reads;
    writes_before = _downstream_writes;
    issue_command('{clean: 1'b1, invalidate: 1'b1});
    expect_int(_downstream_writes, writes_before + 16,
               "clean+invalidate writes dirty lines from both ways");
    expect_word(_backing[(LineA+32'd4)>>2], 32'haaaa_aaaa,
                "clean+invalidate preserves dirty way zero data");
    expect_word(_backing[(LineB+32'd8)>>2], 32'hbbbb_bbbb,
                "clean+invalidate preserves dirty way one data");
    cache_read(LineA + 32'd4, read_data);
    expect_word(read_data, 32'haaaa_aaaa, "clean+invalidate refills first preserved line");
    cache_read(LineB + 32'd8, read_data);
    expect_word(read_data, 32'hbbbb_bbbb, "clean+invalidate refills second preserved line");
    expect_int(_downstream_reads, reads_before + 16, "clean+invalidate invalidates both ways");
  endtask

  // The full directed sequence, run against a minimally spaced bus and a
  // slower one. Behaviour and downstream beat counts must be identical under
  // both: bus back-pressure changes timing, never the traffic.
  task automatic run_sequence(input string label, input int unsigned grant_gap);
    localparam word_t LineA = 32'h0000_0020;
    localparam word_t SameSetStride = word_t'(CacheNumSets * CacheWordsPerLine * 4);
    localparam word_t LineB = LineA + SameSetStride;
    localparam word_t LineC = LineB + SameSetStride;
    localparam word_t LineD = LineC + SameSetStride;
    localparam word_t LineE = LineD + SameSetStride;
    word_t read_data;

    _phase = label;
    _grant_gap = grant_gap;

    _upstream.req = '0;
    _backing = '{default: '0};
    seed_line(LineA, 32'h1000_0000);
    seed_line(LineB, 32'h2000_0000);
    seed_line(LineC, 32'h3000_0000);
    seed_line(LineD, 32'h4000_0000);
    seed_line(LineE, 32'h5000_0000);

    _rst = 1'b1;
    repeat (2) @(posedge _clk);
    #1;
    _rst = 1'b0;

    // A miss response must remain presented after the request payload has been
    // released, even when the upstream master applies response back-pressure.
    _upstream_rsp_ready = 1'b0;
    @(negedge _clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b0,
        addr: LineA + 32'd12,
        write_data: '0,
        write_mask: '0
    };
    while (!_upstream.req_ready) @(negedge _clk);
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    while (!_upstream.rsp.valid) @(negedge _clk);
    repeat (3) begin
      expect_bit(_upstream.rsp.valid, 1'b1, "miss response remains valid under back-pressure");
      expect_word(_upstream.rsp.read_data, 32'h1000_0003,
                  "miss response data remains stable under back-pressure");
      @(negedge _clk);
    end
    read_data = _upstream.rsp.read_data;
    _upstream_rsp_ready = 1'b1;
    @(posedge _clk);
    #1;
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

    _upstream_rsp_ready = 1'b0;
    @(negedge _clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b0,
        addr: LineA + 32'd12,
        write_data: '0,
        write_mask: '0
    };
    #1;
    expect_bit(_upstream.req_ready, 1'b1, "stalled hit request is accepted");
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    while (!_upstream.rsp.valid) @(negedge _clk);
    repeat (3) begin
      expect_bit(_upstream.rsp.valid, 1'b1, "hit response remains valid under back-pressure");
      expect_word(_upstream.rsp.read_data, 32'h1000_0003,
                  "hit response data remains stable under back-pressure");
      @(negedge _clk);
    end
    _upstream_rsp_ready = 1'b1;
    @(posedge _clk);
    #1;

    cache_write(LineA + 32'd12, 32'haaaa_bbbb, 4'b0011);
    cache_write(LineA + 32'd12, 32'hccdd_eeee, 4'b1100);
    cache_read(LineA + 32'd12, read_data);
    expect_word(read_data, 32'hccdd_bbbb, "masked write hit updates selected bytes");
    expect_int(_downstream_writes, 0, "write-back cache defers hit store");

    if (CacheNumWays == 4) begin
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "second same-set line refills correctly");
      cache_read(LineC + 32'd8, read_data);
      expect_word(read_data, 32'h3000_0002, "third same-set line refills correctly");
      cache_read(LineD + 32'd12, read_data);
      expect_word(read_data, 32'h4000_0003, "fourth same-set line refills correctly");
      expect_int(_downstream_writes, 0, "four same-set lines occupy empty ways");
      expect_int(_downstream_reads, 32, "four same-set lines each refill once");

      cache_read(LineA + 32'd12, read_data);
      expect_word(read_data, 32'hccdd_bbbb, "first of four same-set lines remains resident");
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "second of four same-set lines remains resident");
      cache_read(LineC + 32'd8, read_data);
      expect_word(read_data, 32'h3000_0002, "third of four same-set lines remains resident");
      cache_read(LineD + 32'd12, read_data);
      expect_word(read_data, 32'h4000_0003, "fourth of four same-set lines remains resident");
      expect_int(_downstream_reads, 32, "all four resident ways hit");

      // The hit order above leaves dirty A as the tree-PLRU victim. A fifth tag
      // must write A back and refill into its way while retaining B, C, and D.
      cache_read(LineE + 32'd8, read_data);
      expect_word(read_data, 32'h5000_0002, "fifth same-set tag refills correctly");
      expect_int(_downstream_writes, 8, "dirty PLRU victim writes back eight beats");
      expect_int(_downstream_reads, 40, "fifth same-set tag refills eight beats");
      expect_word(_backing[(LineA+32'd12)>>2], 32'hccdd_bbbb,
                  "dirty PLRU write-back preserves modified data");
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "PLRU replacement retains second way");
      cache_read(LineC + 32'd8, read_data);
      expect_word(read_data, 32'h3000_0002, "PLRU replacement retains third way");
      cache_read(LineD + 32'd12, read_data);
      expect_word(read_data, 32'h4000_0003, "PLRU replacement retains fourth way");
      expect_int(_downstream_reads, 40, "three non-victim ways still hit");
    end else begin
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "second same-set line refills correctly");
      expect_int(_downstream_writes, 0, "two same-set lines occupy empty ways");
      expect_int(_downstream_reads, 16, "two same-set lines each refill once");

      cache_read(LineA + 32'd12, read_data);
      expect_word(read_data, 32'hccdd_bbbb, "first of two same-set lines remains resident");
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "second of two same-set lines remains resident");
      expect_int(_downstream_reads, 16, "both resident ways hit");

      cache_read(LineC + 32'd8, read_data);
      expect_word(read_data, 32'h3000_0002, "third same-set tag refills correctly");
      expect_int(_downstream_writes, 8, "dirty LRU victim writes back eight beats");
      expect_int(_downstream_reads, 24, "third same-set tag refills eight beats");
      expect_word(_backing[(LineA+32'd12)>>2], 32'hccdd_bbbb,
                  "dirty LRU write-back preserves modified data");
      cache_read(LineB + 32'd4, read_data);
      expect_word(read_data, 32'h2000_0001, "LRU replacement retains non-victim way");
      expect_int(_downstream_reads, 24, "non-victim way still hits");
    end

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
    _upstream_rsp_ready = 1'b1;
    _command_valid = 1'b0;
    _command_op = '0;
    _command_done_ready = 1'b1;

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_set_associative_cache.vcd");
      $dumpvars(0, tb_set_associative_cache);
    end

    run_sequence("arbiter-paced bus", 2);
    run_sequence("slow bus", 5);
    run_maintenance_sequence();

    if (_errors == 0) begin
      $display("tb_set_associative_cache: PASS (%0d checks)", _checks);
    end else begin
      $display("tb_set_associative_cache: FAIL (%0d errors)", _errors);
      $fatal(1);
    end
    $finish;
  end

  initial begin
    #200us;
    $fatal(1, "tb_set_associative_cache: watchdog timeout");
  end

endmodule
