`timescale 1ns / 1ps

module tb_lru_4_way;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam set_index_t SetA = set_index_t'(3);
  localparam set_index_t SetB = set_index_t'(17);

  logic       _clk;
  logic       _rst;
  logic       _touch_valid;
  set_index_t _touch_set;
  way_index_t _touch_way;
  set_index_t _victim_set;
  way_index_t _victim_way;
  int         _errors;
  int         _checks;

  lru_4_way _dut (
      .clk(_clk),
      .rst(_rst),
      .touch_valid(_touch_valid),
      .touch_set(_touch_set),
      .touch_way(_touch_way),
      .victim_set(_victim_set),
      .victim_way(_victim_way)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  task automatic expect_victim(input set_index_t set, input way_index_t expected,
                               input string what);
    _victim_set = set;
    #1;
    _checks++;
    if (_victim_way !== expected) begin
      $error("%s: expected victim %0d, got %0d", what, expected, _victim_way);
      _errors++;
    end
  endtask

  task automatic touch(input set_index_t set, input way_index_t way);
    @(negedge _clk);
    _touch_valid = 1'b1;
    _touch_set   = set;
    _touch_way   = way;
    @(posedge _clk);
    #1;
    _touch_valid = 1'b0;
  endtask

  initial begin
    _clk = 1'b0;
    _rst = 1'b1;
    _touch_valid = 1'b0;
    _touch_set = '0;
    _touch_way = '0;
    _victim_set = '0;
    _errors = 0;
    _checks = 0;

    if (CacheNumWays != 4) begin
      $fatal(1, "tb_lru_4_way requires CACHE_WAYS=4");
    end

    repeat (2) @(posedge _clk);
    #1;
    _rst = 1'b0;

    expect_victim(SetA, way_index_t'(0), "reset selects way zero");
    expect_victim(SetB, way_index_t'(0), "reset applies independently to every set");

    touch(SetA, way_index_t'(0));
    expect_victim(SetA, way_index_t'(2), "touch way zero points away from left subtree");
    expect_victim(SetB, way_index_t'(0), "touch does not modify another set");

    touch(SetA, way_index_t'(2));
    expect_victim(SetA, way_index_t'(1), "touch way two selects untouched left sibling");

    touch(SetA, way_index_t'(1));
    expect_victim(SetA, way_index_t'(3), "touch way one selects right subtree sibling");

    touch(SetA, way_index_t'(3));
    expect_victim(SetA, way_index_t'(0), "touch way three restores way zero victim");

    touch(SetB, way_index_t'(3));
    expect_victim(SetB, way_index_t'(0), "second set updates independently");
    expect_victim(SetA, way_index_t'(0), "second-set touch preserves first-set state");

    if (_errors == 0) begin
      $display("tb_lru_4_way: PASS (%0d checks)", _checks);
    end else begin
      $display("tb_lru_4_way: FAIL (%0d errors)", _errors);
      $fatal(1);
    end
    $finish;
  end

  initial begin
    #10us;
    $fatal(1, "tb_lru_4_way: watchdog timeout");
  end
endmodule
