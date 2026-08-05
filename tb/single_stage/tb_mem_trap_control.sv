// tb_mem_trap_control.sv - directed checks for memory trap requests.
//
//   make sim  TB=mem_trap_control
//   make wave TB=mem_trap_control

`timescale 1ns / 1ps

module tb_mem_trap_control
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutTicks = 100;

  logic        _valid;
  mem_addr_t   _addr;
  mem_size_t   _mem_size;
  logic        _mem_write_en;
  trap_req_t   _trap;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  mem_trap_control _dut (
    .valid(_valid),
    .addr(_addr),
    .mem_size(_mem_size),
    .mem_write_en(_mem_write_en),
    .trap(_trap)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic drive(input logic valid, input mem_addr_t addr, input mem_size_t mem_size,
                       input logic mem_write_en);
    _valid        = valid;
    _addr         = addr;
    _mem_size     = mem_size;
    _mem_write_en = mem_write_en;
    #1;
  endtask

  task automatic expect_no_trap(input string what);
    expect_bit(_trap.valid, 1'b0, {what, " valid"});
  endtask

  task automatic expect_trap(input trap_src_t src, input mtval_t mtval, input string what);
    expect_bit(_trap.valid, 1'b1, {what, " valid"});
    expect_word(32'(_trap.src), 32'(src), {what, " source"});
    expect_word(_trap.mtval, mtval, {what, " mtval"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mem_trap_control);
    end

    drive(1'b0, 32'h0000_1003, MEM_SIZE_WORD, 1'b0);
    expect_no_trap("invalid memory slot");

    drive(1'b1, 32'h0000_1003, MEM_SIZE_BYTE, 1'b0);
    expect_no_trap("byte load allows any address");

    drive(1'b1, 32'h0000_1002, MEM_SIZE_HALF, 1'b0);
    expect_no_trap("aligned halfword load");

    drive(1'b1, 32'h0000_1001, MEM_SIZE_HALF, 1'b0);
    expect_trap(TRAP_SRC_LOAD_ADDR_MISALIGNED, 32'h0000_1001, "misaligned halfword load");

    drive(1'b1, 32'h0000_1004, MEM_SIZE_WORD, 1'b1);
    expect_no_trap("aligned word store");

    drive(1'b1, 32'h0000_1002, MEM_SIZE_WORD, 1'b1);
    expect_trap(TRAP_SRC_STORE_ADDR_MISALIGNED, 32'h0000_1002, "misaligned word store");

    if (_errors == 0) begin
      $display("tb_mem_trap_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_mem_trap_control: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutTicks);
    $display("tb_mem_trap_control: TIMEOUT after %0d ticks", TimeoutTicks);
    $fatal(1);
  end

endmodule
