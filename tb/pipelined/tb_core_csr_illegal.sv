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

  task automatic drive_idle();
    _ibus.rsp = '0;
    _dbus.rsp = '0;
    _dbus.rsp.ready = 1'b1;
  endtask

  task automatic reset_core();
    @(negedge _clk);
    _rst = 1'b1;
    drive_idle();
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

  task automatic wait_fetch_req(input pc_t exp_addr, input string what);
    int unsigned waits;
    waits = 0;

    #1;
    while (!_ibus.req.valid && waits < 20) begin
      waits++;
      @(negedge _clk);
      #1;
    end

    expect_bit(_ibus.req.valid, 1'b1, {what, " request valid"});
    expect_word(_ibus.req.addr, exp_addr, {what, " request addr"});
  endtask

  task automatic fetch_instr(input pc_t exp_addr, input instr_t instr, input string what);
    wait_fetch_req(exp_addr, what);

    @(posedge _clk);
    #1;
    expect_word(_pc, exp_addr + pc_t'(4), {what, " request advances pc"});

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " response captured"});
    expect_word(_dut._fetched.slot.pc, exp_addr, {what, " response pc"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " response instr"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic offer_squashed_instr(input pc_t exp_addr, input instr_t instr, input string what);
    wait_fetch_req(exp_addr, what);

    @(posedge _clk);
    #1;

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " speculative response may enter IFU output"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " speculative response instr"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic drain_until_trap_entry(input word_t exp_mcause, input string what);
    int unsigned waits;
    waits = 0;

    #1;
    while ((_dut._csr_file._mcause != exp_mcause) && waits < 30) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(_halted, 1'b0, {what, " trap entry does not halt"});
    expect_word(_dut._csr_file._mcause, exp_mcause, {what, " trap writes mcause"});
  endtask

  task automatic check_illegal_csr(input instr_t csr_bad_instr, input string what);
    reset_core();

    fetch_instr(32'h0000_0000, ADDI_X1_X0_7, {what, " older addi"});
    fetch_instr(32'h0000_0004, csr_bad_instr, {what, " illegal csr"});
    offer_squashed_instr(32'h0000_0008, ADDI_X2_X0_9, {what, " younger addi"});

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
    drive_idle();

    check_illegal_csr(csr_instr(CSR_SSTATUS, 5'd0, SYS_F3_RS, 5'd5), "unsupported CSR read");
    check_illegal_csr(csr_instr(CSR_SSTATUS, 5'd3, SYS_F3_RW, 5'd5), "unsupported CSR write");
    check_illegal_csr(csr_instr(CSR_MVENDORID, 5'd3, SYS_F3_RW, 5'd5), "read-only CSR write");

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
