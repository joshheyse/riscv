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
  logic           _trap_from_if_id;
  logic           _mem_order_start;
  logic           _mem_order_busy;
  logic           _pmp_update_wait;
  logic           _execute_wait;
  flow_ctrl_t     _flow;
  pipeline_ctrl_t _pipe_ctrl;

  int unsigned    errors = 0;
  int unsigned    checks = 0;

  pipeline_control _dut (
    .halted(_halted),
    .mem_wait(_dbus_wait),
    .data_stall(_data_stall),
    .trap_from_if_id(_trap_from_if_id),
    .trap_in_flight(_trap_in_flight),
    .flow(_flow),
    .mem_order_start(_mem_order_start),
    .mem_order_busy(_mem_order_busy),
    .pmp_update_wait(_pmp_update_wait),
    .execute_wait(_execute_wait),
    .pipe_ctrl(_pipe_ctrl)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_stage(input stage_ctrl_e got, input stage_ctrl_e exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %0d, expected %0d", $time, what, got, exp);
    end
  endtask

  task automatic expect_control(input stage_ctrl_e fetch_ctrl, input stage_ctrl_e if_id_ctrl,
                                input stage_ctrl_e id_ex_ctrl, input stage_ctrl_e ex_mem_ctrl,
                                input stage_ctrl_e mem_wb_ctrl, input string what);
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
    _trap_from_if_id = 1'b0;
    _mem_order_start = 1'b0;
    _mem_order_busy = 1'b0;
    _pmp_update_wait = 1'b0;
    _execute_wait = 1'b0;
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
    _execute_wait = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE,
                   "multicycle execute holds its instruction and drains older stages");

    clear_inputs();
    _pmp_update_wait = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE,
                   "PMP rebuild holds its instruction and drains older stages");

    clear_inputs();
    _pmp_update_wait = 1'b1;
    _trap_in_flight = 1'b1;
    _flow.action = FLOW_ACTION_TRAP;
    _trap_from_if_id = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE,
                   "younger trap waits behind PMP rebuild");

    clear_inputs();
    _execute_wait = 1'b1;
    _flow.action = FLOW_ACTION_TRAP;
    _trap_from_if_id = 1'b1;
    expect_control(STAGE_HOLD, STAGE_HOLD, STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE,
                   "younger decode trap waits for multicycle execute");

    clear_inputs();
    _execute_wait = 1'b1;
    _flow.action = FLOW_ACTION_TRAP;
    _trap_from_if_id = 1'b0;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "older trap cancels multicycle execute");

    clear_inputs();
    _flow.action = FLOW_ACTION_TRAP;
    _trap_from_if_id = 1'b0;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "trap from older stage flushes decode");

    clear_inputs();
    _flow.action = FLOW_ACTION_TRAP;
    _trap_from_if_id = 1'b1;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   "trap from if_id carries trapping instruction into execute");

    clear_inputs();
    _trap_in_flight = 1'b1;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE, STAGE_ADVANCE,
                   "trap in flight drains to retirement");

    clear_inputs();
    _flow.action = FLOW_ACTION_REDIRECT;
    _flow.redirect.valid = 1'b1;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "redirect flushes younger stages");

    clear_inputs();
    _flow.action = FLOW_ACTION_MRET;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "mret flushes younger stages and advances older stages");

    clear_inputs();
    _flow.action = FLOW_ACTION_SRET;
    expect_control(STAGE_HOLD, STAGE_FLUSH, STAGE_FLUSH, STAGE_ADVANCE, STAGE_ADVANCE,
                   "sret flushes younger stages and advances older stages");

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
