`timescale 1ns / 1ps

module tb_l1_cache;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned BackingWords = 2048;
  localparam mem_addr_t CacheableBase = 32'h0000_0000;
  localparam mem_addr_t CacheableEnd = 32'h0000_2000;
  localparam mem_addr_t MmioAddr = 32'h1000_0000;
  localparam mem_addr_t LineA = 32'h0000_0020;
  localparam mem_addr_t LineB = 32'h0000_1020;

  logic  clk;
  logic  rst;
  logic  _immediate_response;
  int    _errors;
  int    _checks;
  int    _downstream_reads;
  int    _downstream_writes;
  string _phase;

  mem_if _upstream ();
  mem_if _downstream ();

  word_t                               _backing            [0:BackingWords-1];
  word_t                               _mmio_value;
  mem_rsp_t                            _registered_rsp;
  logic     [$clog2(BackingWords)-1:0] _backing_index;
  word_t                               _selected_read_data;

  assign _backing_index = _downstream.req.addr[$clog2(BackingWords)+1:2];
  assign _selected_read_data =
      _downstream.req.addr == MmioAddr ? _mmio_value : _backing[_backing_index];

  // Downstream grant gating, mirroring `mem_arbiter`. The arbiter forwards a
  // request only while it is IDLE; after a grant it spends at least a BUSY and
  // a DRAIN cycle ignoring `req.valid` and returning no `rsp.ready`. Both the
  // cached and the uncached path must therefore hold `req.valid` until
  // `rsp.ready`, the way `ifu` does -- a one-cycle pulse that lands in a
  // refusal window is lost outright.
  int unsigned _grant_gap;
  int unsigned _refuse_left;
  logic        _downstream_grant;

  assign _downstream_grant = _downstream.req.valid && (_refuse_left == 0);

  always_ff @(posedge clk) begin
    if (rst) begin
      _refuse_left <= 0;
    end else if (_downstream_grant) begin
      _refuse_left <= _grant_gap;
    end else if (_refuse_left != 0) begin
      _refuse_left <= _refuse_left - 1;
    end
  end

  always_comb begin
    if (_immediate_response && _downstream_grant) begin
      _downstream.rsp = '{ready: 1'b1, read_data: _selected_read_data};
    end else begin
      _downstream.rsp = _registered_rsp;
    end
  end

  l1_cache #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _dut (
    .clk(clk),
    .rst(rst),
    .upstream(_upstream),
    .downstream(_downstream)
  );

  always #(ClkPeriod / 2) clk = ~clk;

  always_ff @(posedge clk) begin
    if (rst) begin
      _registered_rsp <= '0;
      _downstream_reads <= 0;
      _downstream_writes <= 0;
    end else begin
      _registered_rsp.ready <= !_immediate_response && _downstream_grant;
      if (_downstream_grant) begin
        _registered_rsp.read_data <= _selected_read_data;
        if (_downstream.req.write_en) begin
          _downstream_writes <= _downstream_writes + 1;
          if (_downstream.req.addr == MmioAddr) begin
            if (_downstream.req.write_mask[0]) _mmio_value[7:0] <= _downstream.req.write_data[7:0];
            if (_downstream.req.write_mask[1])
              _mmio_value[15:8] <= _downstream.req.write_data[15:8];
            if (_downstream.req.write_mask[2])
              _mmio_value[23:16] <= _downstream.req.write_data[23:16];
            if (_downstream.req.write_mask[3])
              _mmio_value[31:24] <= _downstream.req.write_data[31:24];
          end else begin
            if (_downstream.req.write_mask[0])
              _backing[_backing_index][7:0] <= _downstream.req.write_data[7:0];
            if (_downstream.req.write_mask[1])
              _backing[_backing_index][15:8] <= _downstream.req.write_data[15:8];
            if (_downstream.req.write_mask[2])
              _backing[_backing_index][23:16] <= _downstream.req.write_data[23:16];
            if (_downstream.req.write_mask[3])
              _backing[_backing_index][31:24] <= _downstream.req.write_data[31:24];
          end
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
    @(negedge clk);
    _upstream.req = '{valid: 1'b1, write_en: 1'b0, addr: addr, default: '0};
    while (!_upstream.rsp.ready) @(negedge clk);
    data = _upstream.rsp.read_data;
    @(posedge clk);
    #1;
    _upstream.req = '0;
  endtask

  task automatic cache_write(input word_t addr, input word_t data, input mem_write_mask_t mask);
    @(negedge clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: addr,
        write_data: data,
        write_mask: mask
    };
    while (!_upstream.rsp.ready) @(negedge clk);
    @(posedge clk);
    #1;
    _upstream.req = '0;
  endtask

  // The full directed sequence, run against a minimally spaced bus and a slower
  // one. Behaviour and downstream traffic counts must be identical under both:
  // bus back-pressure changes timing, never the traffic.
  task automatic run_sequence(input string label, input int unsigned grant_gap);
    word_t read_data;

    _phase = label;
    _grant_gap = grant_gap;
    _immediate_response = 1'b0;
    _upstream.req = '0;
    _backing = '{default: '0};
    _mmio_value = 32'hfeed_face;

    seed_line(LineA, 32'h1000_0000);
    seed_line(LineB, 32'h2000_0000);

    rst = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    rst = 1'b0;

    cache_read(LineA + 32'd4, read_data);
    expect_word(read_data, 32'h1000_0001, "cacheable miss routes through cache");
    expect_int(_downstream_reads, 8, "cacheable miss refills one line");

    cache_read(LineA + 32'd4, read_data);
    expect_word(read_data, 32'h1000_0001, "cacheable hit returns cached data");
    expect_int(_downstream_reads, 8, "cacheable hit avoids downstream request");

    cache_write(LineA + 32'd4, 32'hdead_beef, 4'b1111);
    expect_int(_downstream_writes, 0, "cacheable store remains dirty in cache");

    cache_read(MmioAddr, read_data);
    expect_word(read_data, 32'hfeed_face, "registered MMIO read bypasses cache");
    expect_int(_downstream_reads, 9, "registered MMIO read issues exactly once");

    cache_read(MmioAddr, read_data);
    expect_word(read_data, 32'hfeed_face, "repeated MMIO read is not cached");
    expect_int(_downstream_reads, 10, "repeated MMIO read reaches downstream again");

    cache_write(MmioAddr, 32'h1234_5678, 4'b1111);
    expect_word(_mmio_value, 32'h1234_5678, "MMIO write preserves payload and mask");
    expect_int(_downstream_writes, 1, "registered MMIO write issues exactly once");

    _immediate_response = 1'b1;
    cache_read(MmioAddr, read_data);
    expect_word(read_data, 32'h1234_5678, "same-cycle MMIO response bypasses cache");
    expect_int(_downstream_reads, 11, "same-cycle MMIO request issues exactly once");
    _immediate_response = 1'b0;

    cache_read(LineA + 32'd4, read_data);
    expect_word(read_data, 32'hdead_beef, "MMIO bypass does not evict dirty cache line");
    expect_int(_downstream_reads, 11, "post-MMIO cache hit avoids downstream request");

    cache_read(LineB + 32'd4, read_data);
    expect_word(read_data, 32'h2000_0001, "conflicting cacheable line refills correctly");
    expect_int(_downstream_writes, 9, "dirty cache line writes back after later conflict");
    expect_int(_downstream_reads, 19, "conflicting line performs one refill");
    expect_word(_backing[(LineA+32'd4)>>2], 32'hdead_beef,
                "dirty line survives intervening MMIO transactions");

  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    _errors = 0;
    _checks = 0;
    _grant_gap = 2;
    _phase = "init";
    _immediate_response = 1'b0;
    _upstream.req = '0;

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_l1_cache.vcd");
      $dumpvars(0, tb_l1_cache);
    end

    run_sequence("arbiter-paced bus", 2);
    run_sequence("slow bus", 5);

    if (_errors == 0) begin
      $display("tb_l1_cache: PASS (%0d checks)", _checks);
    end else begin
      $display("tb_l1_cache: FAIL (%0d errors)", _errors);
      $fatal(1);
    end
    $finish;
  end

  initial begin
    #200us;
    $fatal(1, "tb_l1_cache: watchdog timeout");
  end

endmodule
