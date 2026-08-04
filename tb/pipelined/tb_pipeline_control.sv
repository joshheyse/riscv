// tb_pipeline_control.sv - directed checks for global pipeline advance policy.
//
//   make sim DESIGN=pipelined TB=pipeline_control
//   make wave DESIGN=pipelined TB=pipeline_control

`timescale 1ns / 1ps

module tb_pipeline_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  logic              _halted;
  logic              _ex_mem_valid;
  logic              _ex_mem_mem_write_en;
  writeback_result_t _ex_mem_writeback_result;
  logic              _dbus_ready;
  logic              _data_stall;
  logic              _mem_instr;
  logic              _mem_wait;
  stage_ctrl_t       _fetch_ctrl;
  stage_ctrl_t       _if_id_ctrl;
  stage_ctrl_t       _id_ex_ctrl;
  stage_ctrl_t       _ex_mem_ctrl;
  stage_ctrl_t       _mem_wb_ctrl;

  int unsigned       errors = 0;
  int unsigned       checks = 0;

  pipeline_control _dut (
    .halted(_halted),
    .ex_mem_valid(_ex_mem_valid),
    .ex_mem_mem_write_en(_ex_mem_mem_write_en),
    .ex_mem_writeback_result(_ex_mem_writeback_result),
    .dbus_ready(_dbus_ready),
    .data_stall(_data_stall),
    .mem_instr(_mem_instr),
    .mem_wait(_mem_wait),
    .fetch_ctrl(_fetch_ctrl),
    .if_id_ctrl(_if_id_ctrl),
    .id_ex_ctrl(_id_ex_ctrl),
    .ex_mem_ctrl(_ex_mem_ctrl),
    .mem_wb_ctrl(_mem_wb_ctrl)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_stage(input stage_ctrl_t got, input stage_ctrl_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %0d, expected %0d", $time, what, got, exp);
    end
  endtask

  task automatic expect_control(input logic mem_instr, input logic mem_wait,
                                input stage_ctrl_t fetch_ctrl, input stage_ctrl_t if_id_ctrl,
                                input stage_ctrl_t id_ex_ctrl, input stage_ctrl_t ex_mem_ctrl,
                                input stage_ctrl_t mem_wb_ctrl, input string what);
    #1;
    expect_bit(_mem_instr, mem_instr, {what, " mem_instr"});
    expect_bit(_mem_wait, mem_wait, {what, " mem_wait"});
    expect_stage(_fetch_ctrl, fetch_ctrl, {what, " fetch_ctrl"});
    expect_stage(_if_id_ctrl, if_id_ctrl, {what, " if_id_ctrl"});
    expect_stage(_id_ex_ctrl, id_ex_ctrl, {what, " id_ex_ctrl"});
    expect_stage(_ex_mem_ctrl, ex_mem_ctrl, {what, " ex_mem_ctrl"});
    expect_stage(_mem_wb_ctrl, mem_wb_ctrl, {what, " mem_wb_ctrl"});
  endtask

  task automatic clear_inputs();
    _halted = 1'b0;
    _ex_mem_valid = 1'b0;
    _ex_mem_mem_write_en = 1'b0;
    _ex_mem_writeback_result = WB_RESULT_EXEC;
    _dbus_ready = 1'b0;
    _data_stall = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_pipeline_control);
    end

    clear_inputs();
    expect_control(1'b0, 1'b0, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   STAGE_ADVANCE, "empty pipe advances");

    clear_inputs();
    _halted = 1'b1;
    expect_control(1'b0, 1'b0, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD,
                   "halted core stops pipe");

    clear_inputs();
    _data_stall = 1'b1;
    expect_control(1'b0, 1'b0, STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "data stall holds fetch/decode and bubbles execute");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_mem_write_en = 1'b1;
    _dbus_ready = 1'b0;
    expect_control(1'b1, 1'b1, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD,
                   "store waits for dbus ready");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_writeback_result = WB_RESULT_MEM;
    _dbus_ready = 1'b0;
    expect_control(1'b1, 1'b1, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD,
                   "load waits for dbus ready");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_mem_write_en = 1'b1;
    _dbus_ready = 1'b1;
    expect_control(1'b1, 1'b0, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   STAGE_ADVANCE, "ready store lets pipe advance");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    expect_control(1'b0, 1'b0, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   STAGE_ADVANCE, "non-memory writeback does not wait");

    if (errors == 0) begin
      $display("tb_pipeline_control: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_pipeline_control: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutSteps) #1;
    $display("tb_pipeline_control: TIMEOUT after %0d steps", TimeoutSteps);
    $fatal(1);
  end

endmodule
