`timescale 1ns / 1ps

module tb_cache_way;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;

  logic            _clk;
  logic            _rst;
  set_index_t      _set;
  tag_t            _lookup_tag;
  word_index_t     _word_index;
  logic            _data_read_en;
  logic            _data_write_en;
  mem_data_t       _write_data;
  mem_write_mask_t _write_mask;
  cache_meta_op_t  _meta_op;
  tag_t            _install_tag;
  logic            _hit;
  logic            _valid;
  logic            _dirty;
  tag_t            _stored_tag;
  mem_data_t       _read_data;

  int unsigned     _errors;
  int unsigned     _checks;

  cache_way _dut (
    .clk(_clk),
    .rst(_rst),
    .set(_set),
    .lookup_tag(_lookup_tag),
    .word_index(_word_index),
    .data_read_en(_data_read_en),
    .data_write_en(_data_write_en),
    .write_data(_write_data),
    .write_mask(_write_mask),
    .meta_op(_meta_op),
    .install_tag(_install_tag),
    .hit(_hit),
    .valid(_valid),
    .dirty(_dirty),
    .stored_tag(_stored_tag),
    .read_data(_read_data)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  task automatic expect_word(input logic [31:0] actual, input logic [31:0] expected,
                             input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected 0x%08h, got 0x%08h", what, expected, actual);
    end
  endtask

  task automatic expect_tag(input tag_t actual, input tag_t expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected tag 0x%05h, got 0x%05h", what, expected, actual);
    end
  endtask

  task automatic expect_bit(input logic actual, input logic expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected %0b, got %0b", what, expected, actual);
    end
  endtask

  task automatic apply_meta(input set_index_t set, input cache_meta_op_t op,
                            input tag_t install_tag = '0);
    @(negedge _clk);
    _set         = set;
    _meta_op     = op;
    _install_tag = install_tag;
    @(posedge _clk);
    #1;
    _meta_op     = META_NONE;
    _install_tag = '0;
  endtask

  task automatic write_word(input set_index_t set, input word_index_t word_index,
                            input mem_data_t data, input mem_write_mask_t mask,
                            input cache_meta_op_t op = META_NONE, input tag_t install_tag = '0);
    @(negedge _clk);
    _set           = set;
    _word_index    = word_index;
    _write_data    = data;
    _write_mask    = mask;
    _data_write_en = 1'b1;
    _meta_op       = op;
    _install_tag   = install_tag;
    @(posedge _clk);
    #1;
    _data_write_en = 1'b0;
    _meta_op       = META_NONE;
    _install_tag   = '0;
  endtask

  task automatic read_word(input set_index_t set, input word_index_t word_index,
                           input mem_data_t expected, input string what);
    @(negedge _clk);
    _set          = set;
    _word_index   = word_index;
    _data_read_en = 1'b1;
    @(posedge _clk);
    #1;
    _data_read_en = 1'b0;
    expect_word(_read_data, expected, what);
  endtask

  initial begin
    localparam set_index_t SetA = set_index_t'(3);
    localparam set_index_t SetB = set_index_t'(77);
    localparam tag_t TagA = tag_t'(20'h12345);
    localparam tag_t TagB = tag_t'(20'h54321);

    _clk           = 1'b0;
    _rst           = 1'b1;
    _set           = SetA;
    _lookup_tag    = TagA;
    _word_index    = '0;
    _data_read_en  = 1'b0;
    _data_write_en = 1'b0;
    _write_data    = '0;
    _write_mask    = '0;
    _meta_op       = META_NONE;
    _install_tag   = '0;
    _errors        = 0;
    _checks        = 0;

    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;
    #1;

    expect_bit(_valid, 1'b0, "reset clears valid");
    expect_bit(_dirty, 1'b0, "reset clears dirty");
    expect_bit(_hit, 1'b0, "invalid line cannot hit");

    // The final refill beat may update the data RAM and install its metadata
    // on the same edge.
    write_word(SetA, word_index_t'(2), 32'h1122_3344, 4'b1111, META_INSTALL, TagA);
    _lookup_tag = TagA;
    #1;
    expect_bit(_valid, 1'b1, "install marks line valid");
    expect_bit(_dirty, 1'b0, "install marks line clean");
    expect_bit(_hit, 1'b1, "installed tag hits");
    expect_tag(_stored_tag, TagA, "install stores tag");
    read_word(SetA, word_index_t'(2), 32'h1122_3344,
              "simultaneous install and data write stores final beat");

    _lookup_tag = TagB;
    #1;
    expect_bit(_hit, 1'b0, "different tag misses in a valid set");
    expect_bit(_valid, 1'b1, "tag mismatch does not change valid");

    // Each byte lane must retain its old value when its mask bit is clear.
    write_word(SetA, word_index_t'(2), 32'hAABB_CCDD, 4'b0101);
    read_word(SetA, word_index_t'(2), 32'h11BB_33DD, "byte write mask");

    apply_meta(SetA, META_MARK_DIRTY);
    expect_bit(_dirty, 1'b1, "mark-dirty command sets dirty");
    apply_meta(SetA, META_CLEAR_DIRTY);
    expect_bit(_dirty, 1'b0, "clear-dirty command clears dirty");

    // Set selection must isolate both metadata and data.
    write_word(SetB, word_index_t'(2), 32'hDEAD_BEEF, 4'b1111, META_INSTALL, TagB);
    _lookup_tag = TagB;
    #1;
    expect_bit(_hit, 1'b1, "second set hits its own tag");
    read_word(SetB, word_index_t'(2), 32'hDEAD_BEEF, "second set stores independent data");
    _set        = SetA;
    _lookup_tag = TagA;
    #1;
    expect_bit(_hit, 1'b1, "first set remains installed");
    expect_tag(_stored_tag, TagA, "second install does not overwrite first tag");
    read_word(SetA, word_index_t'(2), 32'h11BB_33DD,
              "second-set write does not overwrite first-set data");

    apply_meta(SetA, META_MARK_DIRTY);
    apply_meta(SetA, META_INVALIDATE);
    _lookup_tag = TagA;
    #1;
    expect_bit(_valid, 1'b0, "invalidate clears valid");
    expect_bit(_dirty, 1'b0, "invalidate clears dirty");
    expect_bit(_hit, 1'b0, "invalidated line cannot hit");

    apply_meta(SetA, META_INSTALL, TagB);
    _lookup_tag = TagB;
    #1;
    expect_bit(_hit, 1'b1, "invalidated set can be reinstalled");
    expect_bit(_dirty, 1'b0, "reinstall clears dirty");

    if (_errors == 0) begin
      $display("tb_cache_way: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_cache_way: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_cache_way: watchdog timeout");
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_cache_way);
    end
  end

endmodule
