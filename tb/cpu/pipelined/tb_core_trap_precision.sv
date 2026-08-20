// tb_core_trap_precision.sv - precise-trap ordering checks.
//
//   make sim DESIGN=pipelined TB=core_trap_precision
//   make wave DESIGN=pipelined TB=core_trap_precision

`timescale 1ns / 1ps

module tb_core_trap_precision
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 600;

  localparam instr_t ADDI_X1_X0_7 = 32'h0070_0093;
  localparam instr_t ILLEGAL = 32'h0000_0000;
  localparam instr_t ADDI_X2_X0_9 = 32'h0090_0113;

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

  // The younger instruction is left in memory for the core to fetch
  // speculatively; the trap redirect is what must stop it retiring. mtvec is
  // zero, so the handler is the start of the program again.
  task automatic load_program();
    for (int unsigned word_idx = 0; word_idx < 16; word_idx++) begin
      _bus._store[word_idx] = 32'h0000_0013;  // nop
    end
    _bus._store[0] = ADDI_X1_X0_7;
    _bus._store[1] = ILLEGAL;
    _bus._store[2] = ADDI_X2_X0_9;
  endtask

  task automatic reset_core();
    @(negedge _clk);
    _rst = 1'b1;
    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;
  endtask

  task automatic drain_until_trap_entry();
    int unsigned waits;
    waits = 0;

    #1;
    while ((_dut._csr_file._mcause != 32'h0000_0002) && waits < 80) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(_halted, 1'b0, "trap entry does not halt");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "trap eventually writes mcause");
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_trap_precision);
    end

    _rst = 1'b1;
    load_program();
    reset_core();

    _dut._reg_file._regs[1] = '0;
    _dut._reg_file._regs[2] = '0;

    drain_until_trap_entry();

    expect_word(_dut._reg_file._regs[1], 32'h0000_0007, "older instruction commits before trap");
    expect_word(_dut._reg_file._regs[2], 32'h0000_0000, "younger instruction is squashed");
    expect_word(_dut._csr_file._mepc, 32'h0000_0004, "mepc points at trapped instruction");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "mcause records illegal instruction");
    expect_word(_dut._csr_file._mtval, ILLEGAL, "mtval records trapped instruction bits");

    if (_errors == 0) begin
      $display("tb_core_trap_precision: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_trap_precision: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_trap_precision: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
