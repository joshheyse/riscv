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

  logic           _halted;
  logic           _data_stall;
  logic           _dbus_wait;
  logic           _trap_in_flight;
  flow_ctrl_t     _flow;
  pipeline_ctrl_t _pipe_ctrl;

  int unsigned    errors = 0;
  int unsigned    checks = 0;

  pipeline_control _dut (
    .halted(_halted),
    .mem_wait(_dbus_wait),
    .data_stall(_data_stall),
    .trap_in_flight(_trap_in_flight),
    .flow(_flow),
    .pipe_ctrl(_pipe_ctrl)
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

  task automatic expect_control(input stage_ctrl_t fetch_ctrl, input stage_ctrl_t if_id_ctrl,
                                input stage_ctrl_t id_ex_ctrl, input stage_ctrl_t ex_mem_ctrl,
                                input stage_ctrl_t mem_wb_ctrl, input string what);
    #1;
    expect_stage(_pipe_ctrl.fetch, fetch_ctrl, {what, " fetch_ctrl"});
    expect_stage(_pipe_ctrl.if_id, if_id_ctrl, {what, " if_id_ctrl"});
    expect_stage(_pipe_ctrl.id_ex, id_ex_ctrl, {what, " id_ex_ctrl"});
    expect_stage(_pipe_ctrl.ex_mem, ex_mem_ctrl, {what, " ex_mem_ctrl"});
    expect_stage(_pipe_ctrl.mem_wb, mem_wb_ctrl, {what, " mem_wb_ctrl"});
  endtask

  task automatic clear_inputs();
    _halted = 1'b0;
    _data_stall = 1'b0;
    _dbus_wait = 1'b0;
    _trap_in_flight = 1'b0;
    _flow = '0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_pipeline_control);
    end

    clear_inputs();
    expect_control(STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   "empty pipe advances");

    clear_inputs();
    _halted = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD,
                   "halted core stops pipe");

    clear_inputs();
    _data_stall = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "data stall holds fetch/decode and bubbles execute");

    clear_inputs();
    _dbus_wait = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_HOLD,
                   "memory wait stops pipe");

    clear_inputs();
    _flow.action = FLOW_ACTION_TRAP;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_FLUSH, STAGE_FLUSH,
                   "retired trap flushes pipe");

    clear_inputs();
    _trap_in_flight = 1'b1;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   "trap in flight drains to retirement");

    clear_inputs();
    _flow.action = FLOW_ACTION_REDIRECT;
    _flow.redirect.valid = 1'b1;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "redirect flushes younger stages");

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
