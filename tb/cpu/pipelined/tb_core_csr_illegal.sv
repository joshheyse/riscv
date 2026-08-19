// tb_core_csr_illegal.sv - illegal CSR access trap checks.
//
//   make sim DESIGN=pipelined TB=core_csr_illegal
//   make wave DESIGN=pipelined TB=core_csr_illegal

`timescale 1ns / 1ps

module tb_core_csr_illegal
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 600;

  localparam instr_t ADDI_X1_X0_7 = 32'h0070_0093;
  localparam instr_t ADDI_X2_X0_9 = 32'h0090_0113;
  localparam word_t X5Sentinel = 32'ha5a5_5a5a;
  localparam word_t X3WriteValue = 32'hffff_ffff;

  logic      _clk;
  logic      _rst;
  logic      _halted;
  pc_t       _pc;

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

  // The younger instruction is left in memory to be fetched speculatively; the
  // trap redirect is what must stop it retiring. mtvec is zero, so the handler
  // is the start of the program again.
  task automatic load_program(input instr_t csr_bad_instr);
    for (int unsigned word_idx = 0; word_idx < 16; word_idx++) begin
      _bus._store[word_idx] = 32'h0000_0013;  // nop
    end
    _bus._store[0] = ADDI_X1_X0_7;
    _bus._store[1] = csr_bad_instr;
    _bus._store[2] = ADDI_X2_X0_9;
  endtask

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

  task automatic reset_core();
    @(negedge _clk);
    _rst = 1'b1;
    repeat (2) @(posedge _clk);

    _dut._reg_file._regs[1] = '0;
    _dut._reg_file._regs[2] = '0;
    _dut._reg_file._regs[3] = X3WriteValue;
    _dut._reg_file._regs[5] = X5Sentinel;

    @(negedge _clk);
    _rst = 1'b0;
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");
  endtask

  task automatic drain_until_trap_entry(input word_t exp_mcause, input string what);
    int unsigned waits;
    waits = 0;

    #1;
    while ((_dut._csr_file._mcause != exp_mcause) && waits < 80) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(_halted, 1'b0, {what, " trap entry does not halt"});
    expect_word(_dut._csr_file._mcause, exp_mcause, {what, " trap writes mcause"});
  endtask

  task automatic check_illegal_csr(input instr_t csr_bad_instr, input string what);
    load_program(csr_bad_instr);
    reset_core();

    drain_until_trap_entry(32'h0000_0002, what);

    expect_word(_dut._reg_file._regs[1], 32'h0000_0007, {what, " older instruction commits"});
    expect_word(_dut._reg_file._regs[2], 32'h0000_0000, {what, " younger instruction squashed"});
    expect_word(_dut._reg_file._regs[5], X5Sentinel, {what, " CSR rd write suppressed"});
    expect_word(_dut._csr_file._mepc, 32'h0000_0004, {what, " mepc points at CSR instruction"});
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, {what, " mcause is illegal instruction"});
    expect_word(_dut._csr_file._mtval, csr_bad_instr, {what, " mtval records CSR instruction"});
  endtask

  task automatic check_illegal_csr_from_priv(input priv_mode_t priv_mode,
                                             input instr_t csr_bad_instr, input string what);
    load_program(csr_bad_instr);
    reset_core();
    _dut._csr_file._priv_mode = priv_mode;

    drain_until_trap_entry(32'h0000_0002, what);

    expect_word(_dut._reg_file._regs[1], 32'h0000_0007, {what, " older instruction commits"});
    expect_word(_dut._reg_file._regs[2], 32'h0000_0000, {what, " younger instruction squashed"});
    expect_word(_dut._reg_file._regs[5], X5Sentinel, {what, " CSR rd write suppressed"});
    expect_word(_dut._csr_file._mepc, 32'h0000_0004, {what, " mepc points at CSR instruction"});
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, {what, " mcause is illegal instruction"});
    expect_word(_dut._csr_file._mtval, csr_bad_instr, {what, " mtval records CSR instruction"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_csr_illegal);
    end

    _rst = 1'b1;

    // `sstatus` became a real CSR with supervisor support, so it is no longer
    // an unsupported address. `senvcfg` is the one the core still declines --
    // see the supervisor scope note in CLAUDE.md.
    check_illegal_csr(csr_instr(CSR_SENVCFG, 5'd0, SYS_F3_RS, 5'd5), "unsupported CSR read");
    check_illegal_csr(csr_instr(CSR_SENVCFG, 5'd3, SYS_F3_RW, 5'd5), "unsupported CSR write");
    check_illegal_csr(csr_instr(CSR_MVENDORID, 5'd3, SYS_F3_RW, 5'd5), "read-only CSR write");
    check_illegal_csr_from_priv(PRIV_SUPERVISOR, csr_instr(CSR_MSTATUS, 5'd0, SYS_F3_RS, 5'd5),
                                "supervisor access to machine CSR");

    if (_errors == 0) begin
      $display("tb_core_csr_illegal: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_csr_illegal: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_csr_illegal: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
