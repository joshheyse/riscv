// tb_pipeline_control.sv - directed checks for global pipeline advance policy.
//
//   make sim DESIGN=pipelined TB=pipeline_control
//   make wave DESIGN=pipelined TB=pipeline_control

`timescale 1ns / 1ps

module tb_pipeline_control
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  logic        _halted;
  logic        _ex_mem_valid;
  logic        _ex_mem_mem_write_en;
  result_src_t _ex_mem_result_src;
  logic        _dbus_ready;
  logic        _data_stall;
  logic        _mem_instr;
  logic        _mem_wait;
  logic        _pipe_en;
  logic        _fetch_en;

  int unsigned errors = 0;
  int unsigned checks = 0;

  pipeline_control _dut (
    .halted(_halted),
    .ex_mem_valid(_ex_mem_valid),
    .ex_mem_mem_write_en(_ex_mem_mem_write_en),
    .ex_mem_result_src(_ex_mem_result_src),
    .dbus_ready(_dbus_ready),
    .data_stall(_data_stall),
    .mem_instr(_mem_instr),
    .mem_wait(_mem_wait),
    .pipe_en(_pipe_en),
    .fetch_en(_fetch_en)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_control(input logic mem_instr, input logic mem_wait, input logic pipe_en,
                                input logic fetch_en, input string what);
    #1;
    expect_bit(_mem_instr, mem_instr, {what, " mem_instr"});
    expect_bit(_mem_wait, mem_wait, {what, " mem_wait"});
    expect_bit(_pipe_en, pipe_en, {what, " pipe_en"});
    expect_bit(_fetch_en, fetch_en, {what, " fetch_en"});
  endtask

  task automatic clear_inputs();
    _halted = 1'b0;
    _ex_mem_valid = 1'b0;
    _ex_mem_mem_write_en = 1'b0;
    _ex_mem_result_src = RESULT_ALU;
    _dbus_ready = 1'b0;
    _data_stall = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_pipeline_control);
    end

    clear_inputs();
    expect_control(1'b0, 1'b0, 1'b1, 1'b1, "empty pipe advances");

    clear_inputs();
    _halted = 1'b1;
    expect_control(1'b0, 1'b0, 1'b0, 1'b0, "halted core stops pipe");

    clear_inputs();
    _data_stall = 1'b1;
    expect_control(1'b0, 1'b0, 1'b1, 1'b0, "data stall only stops fetch");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_mem_write_en = 1'b1;
    _dbus_ready = 1'b0;
    expect_control(1'b1, 1'b1, 1'b0, 1'b0, "store waits for dbus ready");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_result_src = RESULT_MEM;
    _dbus_ready = 1'b0;
    expect_control(1'b1, 1'b1, 1'b0, 1'b0, "load waits for dbus ready");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    _ex_mem_mem_write_en = 1'b1;
    _dbus_ready = 1'b1;
    expect_control(1'b1, 1'b0, 1'b1, 1'b1, "ready store lets pipe advance");

    clear_inputs();
    _ex_mem_valid = 1'b1;
    expect_control(1'b0, 1'b0, 1'b1, 1'b1, "non-memory writeback does not wait");

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
