// tb_core_csr.sv - pipelined core CSR instruction integration checks.
//
//   make sim DESIGN=pipelined TB=core_csr
//   make wave DESIGN=pipelined TB=core_csr

`timescale 1ns / 1ps

module tb_core_csr
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 900;
  localparam int unsigned ProgramWords = 32;
  localparam instr_t Nop = 32'h0000_0013;  // addi x0, x0, 0

  logic      _clk;
  logic      _rst;
  logic      _halted;
  pc_t       _pc;
  instr_t    _program         [ProgramWords-1:0];

  /* verilator lint_off UNUSEDSIGNAL */
  logic      _mmio_write;
  mem_addr_t _mmio_write_addr;
  mem_data_t _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem ();
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

  // One backing model serves both streams: `core` has a single memory port and
  // the L1 caches are bypass at its default (empty) cacheable range.
  tb_core_bus #(
    .Words(ProgramWords)
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

  function automatic instr_t csr_instr(input logic [11:0] csr, input regaddr_t rs1_or_zimm,
                                       input sys_funct3_t funct3, input regaddr_t rd);
    return {csr, rs1_or_zimm, funct3, rd, OP_SYSTEM};
  endfunction

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

  task automatic load_program();
    for (int i = 0; i < ProgramWords; i++) begin
      _program[i] = Nop;
    end

    _program[0]  = csr_instr(CSR_MSTATUS, 5'd1, SYS_F3_RW, 5'd5);
    _program[3]  = csr_instr(CSR_MSTATUS, 5'd2, SYS_F3_RS, 5'd6);
    _program[6]  = csr_instr(CSR_MSTATUS, 5'd3, SYS_F3_RC, 5'd7);
    _program[9]  = csr_instr(CSR_MSTATUS, 5'd31, SYS_F3_RWI, 5'd8);
    _program[12] = csr_instr(CSR_MSTATUS, 5'd0, SYS_F3_RSI, 5'd9);
    _program[15] = csr_instr(CSR_MSTATUS, 5'd0, SYS_F3_RC, 5'd10);
    _program[18] = csr_instr(CSR_MSTATUS, 5'd4, SYS_F3_RW, 5'd0);
    // Park the core here. The backing store wraps like real memory, so without
    // a terminating loop the sequence would re-run and clobber its own results.
    _program[21] = 32'h0000_0063;  // beq x0, x0, 0 -- loops without writing a register

    for (int i = 0; i < ProgramWords; i++) begin
      _bus._store[i] = _program[i];
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_csr);
    end

    _rst = 1'b1;
    load_program();
    _dut._reg_file._regs[1] = 32'h0000_1808;
    _dut._reg_file._regs[2] = 32'h0000_0080;
    _dut._reg_file._regs[3] = 32'h0000_0808;
    _dut._reg_file._regs[4] = 32'hffff_ffff;

    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;

    repeat (500) @(posedge _clk);
    #1;

    expect_word(_dut._reg_file._regs[5], 32'h0000_0000, "csrrw returns old mstatus");
    expect_word(_dut._reg_file._regs[6], 32'h0000_1808, "csrrs returns old mstatus");
    expect_word(_dut._reg_file._regs[7], 32'h0000_1888, "csrrc returns old mstatus");
    expect_word(_dut._reg_file._regs[8], 32'h0000_1880, "csrrwi returns old mstatus");
    expect_word(_dut._reg_file._regs[9], 32'h0000_000a, "csrrsi zimm=0 returns old mstatus");
    expect_word(_dut._reg_file._regs[10], 32'h0000_000a, "csrrc x0 returns old mstatus");
    expect_word(_dut._reg_file._regs[0], 32'h0000_0000, "csrrw rd=x0 does not write x0");
    // mstatus.TSR (bit 22) became writable with supervisor support; the old
    // expectation of 0x000019aa predates it.
    expect_word(_dut._csr_file._mstatus, 32'h0040_19aa, "final csrrw rd=x0 writes mstatus");
    expect_bit(_halted, 1'b0, "legal CSR sequence does not halt");

    if (_errors == 0) begin
      $display("tb_core_csr: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_csr: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_csr: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
