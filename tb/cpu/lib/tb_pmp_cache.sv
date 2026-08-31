`timescale 1ns / 1ps

// Focused regression for cacheline PMP metadata.
//
//   make sim TB=pmp_cache

module tb_pmp_cache;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned BackingWords = 4096;
  localparam mem_addr_t LineAddress = 32'h0000_0020;

  localparam pmp_annotation_t ReadOnly = '{
      valid: 1'b1,
      read: 1'b1,
      write: 1'b0,
      execute: 1'b0
  };

  logic _clk;
  logic _rst;
  int unsigned _checks;
  int unsigned _errors;
  int unsigned _downstream_reads;
  int unsigned _downstream_writes;

  mem_if _upstream (
    _clk,
    _rst
  );
  mem_if _downstream (
    _clk,
    _rst
  );
  cache_command_if _cache_command ();

  word_t _backing [0:BackingWords-1];
  logic [index_width(BackingWords)-1:0] _backing_index;

  assign _backing_index = _downstream.req.addr[index_width(BackingWords)+1:2];
  assign _downstream.req_ready = 1'b1;
  assign _downstream.rsp = _downstream.req.valid ? '{
      valid: 1'b1,
      read_data: _backing[_backing_index],
      fault: MMU_FAULT_NONE,
      pmp_annotation: ReadOnly
  } : '0;
  assign _upstream.rsp_ready = 1'b1;
  assign _cache_command.valid = 1'b0;
  assign _cache_command.op = '0;
  assign _cache_command.done_ready = 1'b1;

  set_associative_cache #(
      .PmpEnabled(1'b1)
  ) _dut (
      .clk(_clk),
      .rst(_rst),
      .upstream(_upstream),
      .downstream(_downstream),
      .cache_command(_cache_command)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _downstream_reads <= 0;
      _downstream_writes <= 0;
    end else if (_downstream.req.valid && _downstream.req_ready) begin
      if (_downstream.req.write_en) begin
        _downstream_writes <= _downstream_writes + 1;
      end else begin
        _downstream_reads <= _downstream_reads + 1;
      end
    end
  end

  task automatic expect_bit(input logic actual, input logic expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected %0b, got %0b", what, expected, actual);
    end
  endtask

  task automatic expect_word(input word_t actual, input word_t expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected 0x%08h, got 0x%08h", what, expected, actual);
    end
  endtask

  task automatic expect_fault(input mmu_fault_e actual, input mmu_fault_e expected,
                              input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected fault %0d, got %0d", what, expected, actual);
    end
  endtask

  task automatic cache_access(input mem_addr_t addr, input mmu_access_e access,
                              input priv_mode_e privilege, input logic write_en,
                              input mem_data_t write_data, output mem_data_t read_data,
                              output mmu_fault_e fault);
    @(negedge _clk);
    _upstream.req = '{
        valid: 1'b1,
        write_en: write_en,
        addr: addr,
        size: MEM_SIZE_WORD,
        access: access,
        privilege: privilege,
        write_data: write_data,
        write_mask: write_en ? 4'b1111 : 4'b0000
    };
    while (!_upstream.req_ready) @(negedge _clk);
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    while (!_upstream.rsp.valid) @(negedge _clk);
    read_data = _upstream.rsp.read_data;
    fault = _upstream.rsp.fault;
    @(posedge _clk);
    #1;
  endtask

  initial begin
    mem_data_t read_data;
    mmu_fault_e fault;

    _clk = 1'b0;
    _rst = 1'b1;
    _checks = 0;
    _errors = 0;
    _downstream_reads = 0;
    _downstream_writes = 0;
    _upstream.req = '0;
    _backing = '{default: '0};
    for (int unsigned beat = 0; beat < CacheWordsPerLine; beat++) begin
      _backing[(LineAddress >> 2) + beat] = 32'h1000_0000 + beat;
    end

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_pmp_cache.vcd");
      $dumpvars(0, tb_pmp_cache);
    end

    repeat (2) @(posedge _clk);
    _rst = 1'b0;

    // The first load fills the line and records the read-only annotation.
    cache_access(LineAddress + 32'd4, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0,
                 '0, read_data, fault);
    expect_fault(fault, MMU_FAULT_NONE, "initial supervisor load succeeds");
    expect_word(read_data, 32'h1000_0001, "initial load returns refill data");
    expect_bit(_downstream_reads == CacheWordsPerLine, 1'b1,
               "initial load refills one cache line");
    expect_bit(_downstream_writes == 0, 1'b1, "initial load performs no write-back");

    // The line is resident, but its metadata must block a supervisor store
    // before the cache mutates data or emits a physical write.
    cache_access(LineAddress + 32'd4, MMU_ACCESS_STORE, PRIV_SUPERVISOR, 1'b1,
                 32'hdead_beef, read_data, fault);
    expect_fault(fault, MMU_FAULT_ACCESS, "read-only metadata rejects supervisor store");
    expect_bit(_downstream_writes == 0, 1'b1, "denied hit emits no physical write");

    // A read using the same metadata remains a hit and does not refill.
    cache_access(LineAddress + 32'd4, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0,
                 '0, read_data, fault);
    expect_fault(fault, MMU_FAULT_NONE, "read-only metadata permits supervisor load");
    expect_word(read_data, 32'h1000_0001, "permitted hit returns cached data");
    expect_bit(_downstream_reads == CacheWordsPerLine, 1'b1,
               "permitted hit emits no refill");

    if (_errors == 0) begin
      $display("tb_pmp_cache: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_pmp_cache: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (10_000) @(posedge _clk);
    $fatal(1, "tb_pmp_cache: watchdog timeout");
  end

endmodule
