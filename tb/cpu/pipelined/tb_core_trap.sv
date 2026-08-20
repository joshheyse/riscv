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
  localparam int unsigned TimeoutCycles = 600;
  localparam instr_t IllegalInstr = 32'h0000_0000;

  logic      _clk;
  logic      _rst;
  logic      _halted;
  pc_t       _pc;

  /* verilator lint_off UNUSEDSIGNAL */
  logic      _mmio_write;
  mem_addr_t _mmio_write_addr;
  mem_data_t _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem (
    _clk,
    _rst
  );
  irq_if _irq ();

  always_comb begin
    _irq.pending.platform = 16'h0000;
    _irq.pending.meip = 1'b0;
    _irq.pending.seip = 1'b0;
    _irq.pending.mtip = 1'b0;
    _irq.pending.stip = 1'b0;
    _irq.pending.msip = 1'b0;
    _irq.pending.ssip = 1'b0;
    _irq.pending.usip = 1'b0;
  end



  int unsigned _errors = 0;
  int unsigned _checks = 0;
  // Advancing to an event rather than a fixed offset: inserting the L1 caches
  // lengthened fetch latency, so cycle counts from the split-bus era no longer
  // line up. A task cannot take the condition as an argument -- inputs are
  // sampled once at call time -- so each wait is spelled out.
  int unsigned _waits;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  // `core` has one memory port and the L1 caches are bypass at its default
  // (empty) cacheable range, so one backing model serves fetch and data alike.
  // Every word holds the illegal instruction under test.
  tb_core_bus #(
    .Words(16)
  ) _bus (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .mmio_wait(0),
    .mmio_read_data('0),
    .mmio_write(_mmio_write),
    .mmio_write_addr(_mmio_write_addr),
    .mmio_write_data(_mmio_write_data)
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

    for (int unsigned word_idx = 0; word_idx < 16; word_idx++) begin
      _bus._store[word_idx] = IllegalInstr;
    end
    _rst = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;

    _waits = 0;
    while (!_dut._ifetch_ifu_cache.req.valid && _waits < 20) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._ifetch_ifu_cache.req.valid, 1'b1, "fetch issues first request");
    expect_word(_dut._ifetch_ifu_cache.req.addr, 32'h0000_0000, "first request address");
    expect_word(_pc, 32'h0000_0004, "request advances pc");

    _waits = 0;
    while (!_dut._fetched.valid && _waits < 60) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures illegal response");
    expect_word(_dut._fetched.slot.pc, 32'h0000_0000, "IFU tags illegal response pc");
    expect_word(_dut._fetched.slot.instr.raw, IllegalInstr, "IFU captures illegal instruction");
    expect_bit(_halted, 1'b0, "fetched illegal instruction does not halt yet");

    // The trap is raised combinationally out of decode, so wait for the
    // instruction to actually be sitting in IF/ID with the trap asserted.
    _waits = 0;
    while (!(_dut._if_id.valid && _dut._id_trap.valid) && _waits < 60) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._id_trap.valid, 1'b1, "illegal instruction asserts trap");
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures illegal instruction");
    expect_word(_dut._if_id.slot.pc, 32'h0000_0000, "IF/ID carries illegal instruction pc");
    expect_word(_dut._if_id.slot.instr.raw, IllegalInstr, "IF/ID carries illegal instruction");
    expect_word(_dut._id_trap.payload.epc, 32'h0000_0000, "trap epc is illegal instruction pc");
    expect_word(_dut._id_trap.payload.cause, 32'h0000_0002, "trap cause is illegal instruction");
    expect_word(_dut._id_trap.payload.tval, IllegalInstr, "trap tval is illegal instruction bits");
    expect_word(_dut._id_trap.payload.handler_pc, 32'h0000_0000,
                "temporary zero mtvec traps to zero");
    expect_bit(_halted, 1'b0, "trap is visible before retirement");

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "decode trap does not halt before retirement");
    expect_bit(_dut._id_ex.valid, 1'b1, "trap enters ID/EX");
    expect_bit(_dut._id_ex.trap.valid, 1'b1, "ID/EX carries trap");

    // Retirement is what commits the trap to the CSR file; wait for that rather
    // than counting cycles.
    _waits = 0;
    while (_dut._csr_file._mcause == 32'h0000_0000 && _waits < 60) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_word(_dut._csr_file._mepc, 32'h0000_0000, "csr file captures mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "csr file captures mcause");
    expect_word(_dut._csr_file._mtval, IllegalInstr, "csr file captures mtval");
    expect_bit(_halted, 1'b0, "retired trap does not halt");
    expect_bit(_dut._if_id.valid, 1'b0, "trap clears IF/ID");
    expect_bit(_dut._id_ex.valid, 1'b0, "trap clears ID/EX");
    expect_bit(_dut._ex_mem.valid, 1'b0, "trap clears EX/MEM");
    expect_bit(_dut._mem_wb.valid, 1'b0, "trap clears MEM/WB");

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
