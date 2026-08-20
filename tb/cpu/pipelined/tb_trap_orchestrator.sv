`timescale 1ns / 1ps

// tb_trap_orchestrator.sv - targeted checks for trap arbitration and holding.
//
//   make sim DESIGN=pipelined TB=trap_orchestrator

module tb_trap_orchestrator
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutCycles = 120;

  logic        _clk;
  logic        _rst;
  logic        _clear_trap;

  trap_stage_t _id_trap;
  trap_stage_t _ex_trap;
  trap_stage_t _mem_trap;
  trap_stage_t _trap;
  logic        _trap_held;
  logic        _trap_in_flight;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  trap_orchestrator _dut (
    .clk(_clk),
    .rst(_rst),
    .id_trap(_id_trap),
    .ex_trap(_ex_trap),
    .mem_trap(_mem_trap),
    .clear_trap(_clear_trap),
    .trap_held(_trap_held),
    .trap(_trap),
    .trap_in_flight(_trap_in_flight)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  initial begin
    _clk = 1'b0;
    forever #(5ns) _clk = ~_clk;
  end

  task automatic tick_and_capture(input int cycles = 1);
    repeat (cycles) begin
      @(posedge _clk);
      #1;
    end
  endtask

  task automatic set_trap(output trap_stage_t trap, input logic valid, input pc_t pc,
                          input pc_t vec_pc, input instr_t raw);
    trap = '{
        valid: valid,
        payload: '{
            epc: pc,
            cause: '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR},
            tval: raw,
            handler_pc: vec_pc,
            target_priv: PRIV_MACHINE
        }
    };
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_trap_orchestrator);
    end

    _rst = 1'b1;
    _clear_trap = 1'b0;
    set_trap(_id_trap, 1'b0, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
    set_trap(_ex_trap, 1'b0, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
    set_trap(_mem_trap, 1'b0, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);

    @(posedge _clk);
    #1;
    expect_bit(_trap_in_flight, 1'b0, "no trapped request after reset cycle");

    @(negedge _clk);
    _rst = 1'b0;
    _clear_trap = 1'b0;
    set_trap(_id_trap, 1'b1, 32'h0000_0008, 32'h0000_0000, 32'h1111_1111);
    set_trap(_ex_trap, 1'b1, 32'h0000_0010, 32'h0000_0004, 32'h2222_2222);
    set_trap(_mem_trap, 1'b1, 32'h0000_0018, 32'h0000_0008, 32'h3333_3333);

    tick_and_capture(1);
    expect_bit(_trap_in_flight, 1'b1, "trap_in_flight asserts with pending trap");
    expect_bit(_trap_held, 1'b1, "trap is held while in-flight");
    expect_word(_trap.payload.epc, 32'h0000_0018, "oldest trap has MEM/WB priority");
    expect_word(_trap.payload.tval, 32'h3333_3333, "oldest trap payload selected");

    @(negedge _clk);
    set_trap(_mem_trap, 1'b0, 32'h0000_0020, 32'h0000_000c, 32'h4444_4444);
    set_trap(_ex_trap, 1'b1, 32'h0000_0028, 32'h0000_0010, 32'h2222_2222);
    set_trap(_id_trap, 1'b1, 32'h0000_0030, 32'h0000_0014, 32'h1111_1111);

    tick_and_capture(1);
    expect_word(_trap.payload.epc, 32'h0000_0018,
                "held trap stays stable while older trap not cleared");
    expect_bit(_trap_in_flight, 1'b1, "trap still in flight while held");
    expect_bit(_trap_held, 1'b1, "trap remains held after clear");

    @(negedge _clk);
    _clear_trap = 1'b1;

    tick_and_capture(1);
    _clear_trap = 1'b0;
    expect_word(_trap.payload.epc, 32'h0000_0028, "next oldest trap selected after clear");
    expect_bit(_trap_in_flight, 1'b1, "trap still in flight from next candidate");

    @(negedge _clk);
    _clear_trap = 1'b1;
    _mem_trap = '0;
    _ex_trap = '0;
    _id_trap = '0;

    tick_and_capture(1);
    _clear_trap = 1'b0;
    expect_bit(_trap_in_flight, 1'b0, "trap_in_flight clears when last trap cleared");
    expect_bit(_trap_held, 1'b0, "trap_held clears when no candidate");
    expect_bit(_trap == '0, 1'b1, "trap bus clears with no candidate");
    if (_errors != 0) begin
      $display("tb_trap_orchestrator: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end

    $display("tb_trap_orchestrator: PASS (%0d checks)", _checks);
    $finish;
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_trap_orchestrator: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
