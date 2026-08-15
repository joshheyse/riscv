`timescale 1ns / 1ps

// tb_core_interrupt.sv - interrupt + precise trap stress.
//
//   make sim DESIGN=pipelined TB=core_interrupt
//   make wave DESIGN=pipelined TB=core_interrupt
//
// Sequence:
//   addi x1, x0, 1
//   lw   x2, 0(x0)
//   add  x3, x2, x0 (dependent on the load)
//
// The load response is stalled briefly to force a memory wait while the dependent
// instruction is in IF_ID, and a machine software interrupt is raised at that
// point. Expected behavior:
//   - addi and lw retire
//   - dependent add does not write back
//   - trap target is the dependent add (older instructions complete first)
`timescale 1ns / 1ps

module tb_core_interrupt
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  );

  localparam realtime      ClkPeriod      = 10ns;
  localparam int unsigned  TimeoutCycles  = 500;

  localparam instr_t       ADDI_X1_1 = 32'h0010_0093;
  localparam instr_t       LW_X2_0   = 32'h0000_2103;
  localparam instr_t       ADD_X3_X2 = 32'h0001_0193;
  localparam instr_t       NOP       = 32'h0000_0013;
  localparam instr_t       SRET      = 32'h1020_0073;
  localparam word_t        LOAD_DATA = 32'h1234_5678;

  logic        _clk;
  logic        _rst;
  logic        _halted;
  pc_t         _pc;

  ibus_if      _ibus();
  dbus_if      _dbus();
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

  core _dut(
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .ibus(_ibus),
    .dbus(_dbus),
      .irq(_irq)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bit(
    input logic got,
    input logic exp,
    input string what
  );
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(
    input word_t got,
    input word_t exp,
    input string what
  );
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
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;
  endtask

  task automatic wait_fetch_req(
    input pc_t        exp_addr,
    input string      what,
    input int unsigned timeout
  );
    int unsigned waits;

    waits = 0;
    #1;
    while (!(_ibus.req.valid && (_ibus.req.addr == exp_addr)) && (waits < timeout)) begin
      @(negedge _clk);
      #1;
      waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_ibus.req.valid, 1'b1, {what, " request valid"});
    expect_word(_ibus.req.addr, exp_addr, {what, " request addr"});
  endtask

  task automatic fetch_instr(
    input pc_t   exp_addr,
    input instr_t instr,
    input string what
  );
    wait_fetch_req(exp_addr, what, 24);

    @(posedge _clk);
    #1;
    expect_word(_pc, exp_addr + pc_t'(4), {what, " pc advances"});

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " fetched"});
    expect_word(_dut._fetched.slot.pc, exp_addr, {what, " fetched pc"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " fetched instr"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic wait_overlap(
    input int unsigned max_cycles
  );
    int unsigned cycles;
    bit         seen_overlap;

    cycles = 0;
    seen_overlap = 1'b0;

    while ((cycles < max_cycles) && !seen_overlap) begin
      @(posedge _clk);
      #1;
      if (_dut._dbus_wait && _dut._data_stall) begin
        seen_overlap = 1'b1;
      end
      cycles++;
    end

    expect_bit(seen_overlap, 1'b1, "mem_wait and data_stall overlap");
  endtask

  task automatic wait_trap_entry(
    input word_t      cause_expected,
    input int unsigned max_cycles
  );
    int unsigned cycles;

    cycles = 0;
    while ((_dut._csr_file._mcause != cause_expected) && (cycles < max_cycles)) begin
      @(posedge _clk);
      #1;
      cycles++;
    end
    expect_word(_dut._csr_file._mcause, cause_expected, "trap cause is machine software interrupt");
  endtask

  task automatic expect_interrupt_request(input logic exp_valid, input trap_src_t exp_src,
                                          input string what);
    #1;
    expect_bit(_dut._interrupt_trap_req.valid, exp_valid, {what, " valid"});
    if (exp_valid) begin
      expect_word(32'(_dut._interrupt_trap_req.src), 32'(exp_src), {what, " source"});
    end
  endtask

  task automatic clear_interrupt_state();
    _dut._csr_file._mie = '0;
    _dut._csr_file._mip = '0;
    _dut._csr_file._mideleg = '0;
    _dut._csr_file._mstatus.mie = 1'b0;
    _dut._csr_file._mstatus.sie = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_interrupt);
    end

    _rst = 1'b1;
    drive_idle();
    reset_core();

    // Supervisor interrupt sources follow the existing external, timer,
    // software arbitration pattern and respect supervisor global enable.
    clear_interrupt_state();
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0222;
    _dut._csr_file._mie.seip = 1'b1;
    _dut._csr_file._mip.seip = 1'b1;
    expect_interrupt_request(1'b1, TRAP_SRC_SUPERVISOR_EXTERNAL_INTERRUPT,
                             "delegated supervisor external interrupt");

    clear_interrupt_state();
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0222;
    _dut._csr_file._mie.stip = 1'b1;
    _dut._csr_file._mip.stip = 1'b1;
    expect_interrupt_request(1'b1, TRAP_SRC_SUPERVISOR_TIMER_INTERRUPT,
                             "delegated supervisor timer interrupt");

    clear_interrupt_state();
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0222;
    _dut._csr_file._mie.ssip = 1'b1;
    _dut._csr_file._mip.ssip = 1'b1;
    expect_interrupt_request(1'b1, TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT,
                             "delegated supervisor software interrupt");

    _dut._csr_file._mstatus.sie = 1'b0;
    expect_interrupt_request(1'b0, TRAP_SRC_NONE,
                             "supervisor global disable blocks delegated interrupt");

    _dut._csr_file._priv_mode = PRIV_USER;
    expect_interrupt_request(1'b1, TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT,
                             "lower privilege enables delegated supervisor interrupt");

    _dut._csr_file._priv_mode = PRIV_MACHINE;
    _dut._csr_file._mstatus.sie = 1'b1;
    expect_interrupt_request(1'b0, TRAP_SRC_NONE,
                             "delegated supervisor interrupt cannot preempt machine mode");

    clear_interrupt_state();
    reset_core();

    // Interrupts require machine mode + global/specific enables.
    _dut._csr_file._priv_mode = PRIV_MACHINE;
    _dut._csr_file._mstatus.mie = 1'b1;
    _dut._csr_file._mie.msip = 1'b1;

    _dut._reg_file._regs[1] = 32'h0000_0000;
    _dut._reg_file._regs[2] = 32'h0000_0000;
    _dut._reg_file._regs[3] = 32'hdead_beef;

    fetch_instr(32'h0000_0000, ADDI_X1_1, "addi x1, x0, 1");

    fetch_instr(32'h0000_0004, LW_X2_0, "lw x2, 0(x0)");

    // Stall LSU before the dependent instruction can exit IF/ID on the next
    // transition, forcing mem_wait and creating overlap with load-use data_stall.
    _dbus.rsp.ready = 1'b0;

    fetch_instr(32'h0000_0008, ADD_X3_X2, "add x3, x2, x0");

    _dut._csr_file._mip.msip = 1'b1;
    wait_overlap(24);

    @(negedge _clk);
    _dbus.rsp.read_data = LOAD_DATA;
    _dbus.rsp.ready = 1'b1;

    wait_trap_entry(32'h8000_0003, 120);
    expect_word(_dut._csr_file._mepc, 32'h0000_0008, "trap mepc points at dependent instruction");

    // Sanity: core should stay running (not a synthetic halt trap).
    expect_bit(_halted, 1'b0, "trap entry does not halt");

    // Older instructions retire and write back; younger dependent gets squashed.
    expect_word(_dut._reg_file._regs[1], 32'h0000_0001, "older addi committed");
    expect_word(_dut._reg_file._regs[2], LOAD_DATA, "load result committed before trap");
    expect_word(_dut._reg_file._regs[3], 32'hdead_beef, "squashed dependent add does not write x3");

    // Let a delegated supervisor software interrupt traverse the complete
    // pipeline, update supervisor CSRs, redirect to stvec, and return via sret.
    reset_core();
    _dut._csr_file._stvec.base = 30'h0000_0010;
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0002;
    _dut._csr_file._mie.ssip = 1'b1;
    _dut._csr_file._mepc = 32'h1111_1110;
    _dut._csr_file._mcause = '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT};
    _dut._csr_file._mtval = 32'h2222_2222;

    fetch_instr(32'h0000_0000, NOP, "supervisor instruction before interrupt");
    _dut._csr_file._mip.ssip = 1'b1;

    begin
      int unsigned waits;
      waits = 0;
      while (((_dut._csr_file._scause != 32'h8000_0001) ||
              (_dut._csr_file._priv_mode != PRIV_SUPERVISOR)) && (waits < 120)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < 120, 1'b1, "delegated supervisor interrupt retires");
    end

    expect_word(_dut._csr_file._sepc, 32'h0000_0000, "supervisor interrupt sepc");
    expect_word(_dut._csr_file._scause, 32'h8000_0001, "supervisor interrupt scause");
    expect_word(_dut._csr_file._stval, 32'h0000_0000, "supervisor interrupt stval");
    expect_word(_dut._csr_file._mepc, 32'h1111_1110, "supervisor interrupt preserves mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0003, "supervisor interrupt preserves mcause");
    expect_word(_dut._csr_file._mtval, 32'h2222_2222, "supervisor interrupt preserves mtval");

    _dut._csr_file._mip.ssip = 1'b0;
    fetch_instr(32'h0000_0040, SRET, "supervisor interrupt handler sret");

    begin
      int unsigned waits;
      waits = 0;
      while (((_dut._csr_file._priv_mode != PRIV_SUPERVISOR) ||
              !(_ibus.req.valid && (_ibus.req.addr == 32'h0000_0000))) && (waits < 120)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < 120, 1'b1, "sret resumes interrupted supervisor instruction");
      expect_bit(_dut._csr_file._priv_mode == PRIV_SUPERVISOR, 1'b1,
                 "interrupt sret restores supervisor mode");
      expect_word(_ibus.req.addr, 32'h0000_0000, "interrupt sret resumes at sepc");
    end

    if (_errors == 0) begin
      $display("tb_core_interrupt: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_interrupt: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_interrupt: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
