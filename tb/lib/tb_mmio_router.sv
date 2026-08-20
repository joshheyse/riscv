// Self-checking tests for mmio_router.
//
//   make sim  TB=mmio_router
//   make wave TB=mmio_router

`timescale 1ns / 1ps

module tb_mmio_router
  import riscv_pkg::*;
();

  localparam realtime Timeout = 200ns;
  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned NumSources = 3;
  localparam int unsigned MemIdx = 0;
  localparam logic [NumSources-1:0] SourceMemIdx = 3'b001;
  localparam logic [NumSources-1:0] SourceRoIdx = 3'b010;
  localparam logic [NumSources-1:0] SourceRwIdx = 3'b100;

  localparam mmio_source_t _source_map[NumSources] = '{
      '{start_addr: 32'h0000_0000, end_addr: 32'h0000_0040, writeable: 1'b1},
      '{start_addr: 32'h0000_0000, end_addr: 32'h0000_0010, writeable: 1'b0},
      '{start_addr: 32'h0000_0010, end_addr: 32'h0000_0020, writeable: 1'b1}
  };

  logic _clk;
  logic _rst;

  mem_if _dbus_mem (
    _clk,
    _rst
  );
  mem_if _mmio_mem[NumSources] (
    _clk,
    _rst
  );

  logic            [NumSources-1:0] _source_selected;
  logic            [NumSources-1:0] _source_ready;
  logic            [NumSources-1:0] _source_req_valid;
  logic            [NumSources-1:0] _source_req_write_en;
  mem_addr_t                        _source_req_addr     [NumSources];
  mem_data_t                        _source_req_data     [NumSources];
  mem_write_mask_t                  _source_req_mask     [NumSources];

  int unsigned                      _errors = 0;
  int unsigned                      _checks = 0;

  mmio_router #(
    .NumSources(NumSources),
    .MemIdx(MemIdx),
    .MemHasPrio(1'b1),
    .SourceMap(_source_map)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .dbus(_dbus_mem),
    .selected(_source_selected),
    .mem(_mmio_mem)
  );

  genvar _gi;
  generate
    for (_gi = 0; _gi < NumSources; _gi++) begin : GEN_IFACE_CAPTURE
      assign _mmio_mem[_gi].rsp.valid     = _source_ready[_gi];
      assign _mmio_mem[_gi].req_ready     = 1'b1;
      assign _mmio_mem[_gi].rsp.read_data = 32'h1000_0000 + _gi;

      assign _source_req_valid[_gi]       = _mmio_mem[_gi].req.valid;
      assign _source_req_write_en[_gi]    = _mmio_mem[_gi].req.write_en;
      assign _source_req_addr[_gi]        = _mmio_mem[_gi].req.addr;
      assign _source_req_data[_gi]        = _mmio_mem[_gi].req.write_data;
      assign _source_req_mask[_gi]        = _mmio_mem[_gi].req.write_mask;
    end
  endgenerate

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got=%0b expected=%0b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input logic [31:0] got, input logic [31:0] exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got=0x%08x expected=0x%08x", $time, what, got, exp);
    end
  endtask

  task automatic expect_vector(input logic [NumSources-1:0] got, input logic [NumSources-1:0] exp,
                               input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got=0b%0b expected=0b%0b", $time, what, got, exp);
    end
  endtask

  task automatic apply_and_check(input logic req_valid, input logic req_write_en,
                                 input mem_addr_t req_addr, input mem_data_t req_write_data,
                                 input mem_write_mask_t req_write_mask,
                                 input logic [NumSources-1:0] exp_selected, input logic exp_ready,
                                 input mem_data_t exp_read_data, input string what);
    logic exp_source_valid;
    logic exp_source_write_en;

    _dbus_mem.req = '{
        valid: req_valid,
        write_en: req_write_en,
        addr: req_addr,
        write_data: req_write_data,
        write_mask: req_write_mask
    };

    #1;

    expect_vector(_source_selected, exp_selected, {what, ".selected"});
    expect_bit(_dbus_mem.rsp.valid, exp_ready, {what, ".rsp.valid"});
    expect_word(_dbus_mem.rsp.read_data, exp_read_data, {what, ".rsp.read_data"});

    for (int unsigned _i = 0; _i < NumSources; _i++) begin
      exp_source_valid = req_valid && exp_selected[_i];
      exp_source_write_en  = req_valid && req_write_en && exp_selected[_i] && _source_map[_i].writeable;

      expect_bit(_source_req_valid[_i], exp_source_valid, {
                 what, ".source", $sformatf("[%0d]", _i), ".req.valid"});
      expect_bit(_source_req_write_en[_i], exp_source_write_en, {
                 what, ".source", $sformatf("[%0d]", _i), ".req.write_en"});
      expect_word(_source_req_addr[_i], req_addr, {
                  what, ".source", $sformatf("[%0d]", _i), ".req.addr"});
      expect_word(_source_req_data[_i], req_write_data, {
                  what, ".source", $sformatf("[%0d]", _i), ".req.write_data"});
      expect_word({28'b0, _source_req_mask[_i]}, {28'b0, req_write_mask}, {
                  what, ".source", $sformatf("[%0d]", _i), ".req.write_mask"});
    end
  endtask

  task automatic clear_dbus_request();
    _dbus_mem.req = '{valid: 1'b0, write_en: 1'b0, addr: '0, write_data: '0, write_mask: '0};
  endtask

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mmio_router);
    end

    // Every source answers in the cycle it is accepted, so the router never
    // has an outstanding transaction and behaves combinationally here.
    _source_ready = '1;
    clear_dbus_request();
    _rst = 1'b1;
    @(posedge _clk);
    #1;
    _rst = 1'b0;

    // default memory overlaps MMIO ranges; MMIO has priority and must win.
    apply_and_check(1'b1, 1'b0, 32'h0000_0008, 32'h0000_0000, 4'b0000, SourceRoIdx, 1'b1,
                    32'h1000_0001, "dmem_priority_mmio_read");

    // Read-only MMIO ignores writes (write_en is blocked on output).
    apply_and_check(1'b1, 1'b1, 32'h0000_0004, 32'h1234_5678, 4'b1111, SourceRoIdx, 1'b1,
                    32'h1000_0001, "ro_mmio_write_blocked");

    // Writable MMIO receives and drives a write request.
    apply_and_check(1'b1, 1'b1, 32'h0000_0014, 32'hdead_beef, 4'b1111, SourceRwIdx, 1'b1,
                    32'h1000_0002, "rw_mmio_write");

    // default memory-only address range selects default memory path.
    apply_and_check(1'b1, 1'b0, 32'h0000_0030, 32'h0000_0000, 4'b0000, SourceMemIdx, 1'b1,
                    32'h1000_0000, "dmem_after_mmio_ranges");

    // When selected source stalls, router reflects backpressure upstream.
    _source_ready[2] = 1'b0;
    apply_and_check(1'b1, 1'b0, 32'h0000_0014, 32'h0000_0000, 4'b0000, SourceRwIdx, 1'b0,
                    32'h1000_0002, "rw_mmio_wait");
    _source_ready[2] = 1'b1;

    // Unmapped request goes to no source; response drives zero from mux.
    apply_and_check(1'b1, 1'b0, 32'h2000_0000, 32'h0000_0000, 4'b0000, 3'b000, 1'b1, 32'h0000_0000,
                    "unmapped_read");

    // Inactive request: valid=0 should suppress all source req.valid, while
    // selected can still be address-based.
    clear_dbus_request();
    _dbus_mem.req = '{
        valid: 1'b0,
        write_en: 1'b0,
        addr: 32'h0000_0008,
        write_data: 32'h1234_5678,
        write_mask: 4'b1111
    };
    #1;
    expect_bit(_source_req_valid[0], 1'b0, "no_request.source0.req.valid");
    expect_bit(_source_req_valid[1], 1'b0, "no_request.source1.req.valid");
    expect_bit(_source_req_valid[2], 1'b0, "no_request.source2.req.valid");
    expect_vector(_source_selected, SourceRoIdx, "no_request.selected");
    expect_bit(_dbus_mem.rsp.valid, 1'b1, "no_request.rsp.valid");

    if (_errors == 0) begin
      $display("tb_mmio_router: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_mmio_router: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #Timeout;
    $display("tb_mmio_router: TIMEOUT");
    $fatal(1);
  end

endmodule
