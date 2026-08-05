// tb_core_trap.sv - trap parity checks for the pipelined core.
//
//   make sim DESIGN=pipelined TB=core_trap
//   make wave DESIGN=pipelined TB=core_trap

`timescale 1ns / 1ps

module tb_core_trap
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;
  localparam instr_t IllegalInstr = 32'h0000_0000;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .ibus(_ibus),
    .dbus(_dbus)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

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
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_trap);
    end

    _ibus.rsp = '0;
    _dbus.rsp = '0;
    _dbus.rsp.ready = 1'b1;
    _rst = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "fetch issues first request");
    expect_word(_ibus.req.addr, 32'h0000_0000, "first request address");

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0004, "request advances pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = IllegalInstr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures illegal response");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU tags illegal response pc");
    expect_word(_dut._fetched.instr.raw, IllegalInstr, "IFU captures illegal instruction");
    expect_bit(_halted, 1'b0, "fetched illegal instruction does not halt yet");

    @(negedge _clk);
    _ibus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures illegal instruction");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID carries illegal instruction pc");
    expect_word(_dut._if_id.instr.raw, IllegalInstr, "IF/ID carries illegal instruction");
    expect_bit(_dut._id_trap.valid, 1'b1, "illegal instruction asserts trap");
    expect_word(_dut._id_trap.payload.mepc, 32'h0000_0000, "trap mepc is illegal instruction pc");
    expect_word(_dut._id_trap.payload.mcause, 32'h0000_0002, "trap mcause is illegal instruction");
    expect_word(_dut._id_trap.payload.mtval, IllegalInstr, "trap mtval is illegal instruction bits");
    expect_word(_dut._id_trap.payload.pc, 32'h0000_0000, "temporary zero mtvec traps to zero");
    expect_bit(_halted, 1'b0, "trap is visible before retirement");

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "decode trap does not halt before retirement");
    expect_bit(_dut._id_ex.valid, 1'b1, "trap enters ID/EX");
    expect_bit(_dut._id_ex.trap.valid, 1'b1, "ID/EX carries trap");

    repeat (3) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "retired trap does not halt");
    expect_bit(_dut._if_id.valid, 1'b0, "trap clears IF/ID");
    expect_bit(_dut._id_ex.valid, 1'b0, "trap clears ID/EX");
    expect_bit(_dut._ex_mem.valid, 1'b0, "trap clears EX/MEM");
    expect_bit(_dut._mem_wb.valid, 1'b0, "trap clears MEM/WB");
    expect_word(_dut._csr_file._mepc, 32'h0000_0000, "csr file captures mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "csr file captures mcause");
    expect_word(_dut._csr_file._mtval, IllegalInstr, "csr file captures mtval");

    if (_errors == 0) begin
      $display("tb_core_trap: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_trap: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_trap: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
