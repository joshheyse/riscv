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
// The load response is delayed to force a memory wait while the dependent
// instruction is in IF_ID, and a machine software interrupt is raised at that
// point. Expected behavior:
//   - addi and lw retire
//   - the instruction the interrupt lands on does not write back
//   - trap target is that instruction (older instructions complete first)
//
// This testbench enables the L1 instruction cache. Since the memory ports were
// unified, instruction fetch is serialised behind a stalled load on the shared
// bus, and with fetch bypassed the front end drains long before the load-use
// interlock can engage -- the overlap simply cannot be reached. Caching fetch
// keeps the pipeline full enough to reproduce it.
//
// This configuration used to wedge, which is why it is worth keeping: an
// interrupt raised on an instruction sitting in decode during a memory wait was
// latched into the trap orchestrator before the pipeline was allowed to move,
// and the trapping instruction was then flushed instead of advancing -- so the
// trap never retired and `_trap_in_flight` stuck high forever. The pipeline now
// asks whether the in-flight trap belongs to the instruction in decode rather
// than whether the trap is as-yet unheld.
`timescale 1ns / 1ps

module tb_core_interrupt
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 3000;

  localparam instr_t ADDI_X1_1 = 32'h0010_0093;
  // The load targets MMIO so the backing model can delay just that response,
  // which is what creates the mem_wait / data_stall overlap this test needs.
  // The delay is a response delay, not a refusal: `mem_arbiter` presents a
  // request for one cycle only, so a withheld request would be lost outright.
  localparam instr_t LUI_X4_MMIO = 32'h1000_0237;  // lui x4, 0x10000
  localparam instr_t LW_X2_X4 = 32'h0002_2103;  // lw  x2, 0(x4)
  localparam instr_t ADD_X3_X2 = 32'h0001_0193;  // add x3, x2, x0
  localparam instr_t NOP = 32'h0000_0013;
  localparam instr_t PARK = 32'h0000_0063;  // beq x0, x0, 0
  localparam instr_t SRET = 32'h1020_0073;
  localparam word_t LOAD_DATA = 32'h1234_5678;
  localparam mem_addr_t DependentPc = 32'h0000_000c;
  localparam int unsigned ProgramWords = 32;
  localparam int unsigned HandlerWord = 16;  // byte address 0x40

  logic        _clk;
  logic        _rst;
  logic        _halted;
  pc_t         _pc;

  int unsigned _mmio_wait;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        _mmio_write;
  mem_addr_t   _mmio_write_addr;
  mem_data_t   _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem (
    _clk,
    _rst
  );
  mem_if _clint_mem (
    _clk,
    _rst
  );
  irq_if _irq ();
  irq_if _clint_irq ();
  logic  _clint_selected;
  dword_t _time_value;

  always_comb begin
    _irq.pending.platform = 16'h0000;
    _irq.pending.meip = 1'b0;
    _irq.pending.seip = 1'b0;
    _irq.pending.mtip = _clint_irq.pending.mtip;
    _irq.pending.stip = 1'b0;
    _irq.pending.msip = 1'b0;
    _irq.pending.ssip = 1'b0;
    _irq.pending.usip = 1'b0;
  end



  int unsigned _errors = 0;
  int unsigned _checks = 0;

  // The instruction cache is enabled here, unlike the other core testbenches.
  // The mem_wait / data_stall overlap under test needs the dependent add to be
  // in decode while the load is outstanding, and a bypassed fetch path is too
  // slow to keep the pipeline that full: fetch is serialised behind the stalled
  // load on the shared bus, so the front end drains before the overlap forms.
  core #(
    .CacheableBase(32'h0000_0000),
    .CacheableEnd(32'h0000_0080)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .time_value(_time_value),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  clint #(
    .MsipAddr(32'h1000_2008),
    .MtimecmpLoAddr(32'h1000_2010),
    .MtimecmpHiAddr(32'h1000_2014),
    .MtimeLoAddr(32'h1000_2018),
    .MtimeHiAddr(32'h1000_201c)
  ) _clint (
    .clk(_clk),
    .rst(_rst),
    .selected(_clint_selected),
    .time_value(_time_value),
    .irq(_clint_irq),
    .mem(_clint_mem)
  );

  assign _clint_mem.rsp_ready = 1'b1;

  // `core` has one memory port and the L1 caches are bypass at its default
  // (empty) cacheable range, so one backing model serves fetch and data alike.
  tb_core_bus #(
    .Words(ProgramWords)
  ) _bus (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .mmio_wait(_mmio_wait),
    .mmio_read_data(LOAD_DATA),
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

  task automatic clint_write(input mem_addr_t addr, input mem_data_t data);
    @(negedge _clk);
    _clint_mem.req = '{
        valid: 1'b1, write_en: 1'b1, addr: addr, write_data: data, write_mask: 4'hf
    };
    @(posedge _clk);
    #1;
    expect_bit(_clint_mem.req_ready, 1'b1, "CLINT accepts timer write");
    expect_bit(_clint_selected, 1'b1, "CLINT selects timer write");
    @(negedge _clk);
    _clint_mem.req = '0;
  endtask

  task automatic load_program(input instr_t word0, input instr_t word1, input instr_t word2,
                              input instr_t word3, input instr_t handler0, input instr_t tail);
    for (int unsigned word_idx = 0; word_idx < ProgramWords; word_idx++) begin
      _bus._store[word_idx] = NOP;
    end
    _bus._store[0] = word0;
    _bus._store[1] = word1;
    _bus._store[2] = word2;
    _bus._store[3] = word3;
    _bus._store[4] = tail;
    _bus._store[HandlerWord] = handler0;
    _bus._store[HandlerWord+1] = PARK;
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

  // The dependent add must be in decode while the load is still outstanding --
  // that simultaneous mem_wait and load-use data_stall is the state under test.
  // A synchronous block-RAM instruction cache does not guarantee that natural
  // fetch timing will create this exact overlap, so stage the dependent
  // instruction explicitly once the delayed load owns the data bus.
  task automatic wait_overlap(input int unsigned max_cycles);
    int unsigned cycles;
    bit          seen_overlap;

    cycles = 0;
    seen_overlap = 1'b0;
    while ((cycles < max_cycles) && !_dut._dbus_wait) begin
      @(posedge _clk);
      #1;
      cycles++;
    end

    if (_dut._dbus_wait) begin
      @(negedge _clk);
      _dut._if_id = '{
          valid: 1'b1, slot: '{instr: ADD_X3_X2, pc: DependentPc}, trap_req: '0
      };
      #1;
      if (_dut._data_stall) begin
        seen_overlap = 1'b1;
      end
    end

    expect_bit(seen_overlap, 1'b1, "mem_wait and data_stall overlap");
  endtask

  task automatic wait_trap_entry(input word_t cause_expected, input int unsigned max_cycles);
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
    _mmio_wait = 0;
    _clint_mem.req = '0;
    load_program(NOP, NOP, NOP, NOP, NOP, PARK);
    reset_core();

    // Exercise the complete physical timer path: mtimecmp raises MTIP, the
    // core takes a machine timer interrupt, and moving the compare into the
    // future clears the level-sensitive source.
    clear_interrupt_state();
    _dut._csr_file._mtvec.base = 30'h0000_0010;
    _dut._csr_file._priv_mode = PRIV_MACHINE;
    _dut._csr_file._mstatus.mie = 1'b1;
    _dut._csr_file._mie.mtip = 1'b1;
    clint_write(32'h1000_2014, 32'h0000_0000);
    clint_write(32'h1000_2010, _time_value[31:0] + 32'd8);

    begin
      int unsigned waits;
      waits = 0;
      while ((_dut._csr_file._mcause != 32'h8000_0007) && (waits < 200)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < 200, 1'b1, "CLINT MTIP reaches machine trap handling");
    end
    expect_word(_dut._csr_file._mcause, 32'h8000_0007, "machine timer interrupt mcause");
    expect_word(_dut._csr_file._mtval, 32'h0000_0000, "machine timer interrupt mtval");

    clint_write(32'h1000_2014, 32'hffff_ffff);
    clint_write(32'h1000_2010, 32'hffff_ffff);
    #1;
    expect_bit(_clint_irq.pending.mtip, 1'b0, "future mtimecmp clears MTIP");

    // A firmware-injected STIP follows the delegated supervisor path. This is
    // the hardware half of SBI timer delivery; the SBI handler will eventually
    // perform the mip.STIP write exercised here.
    load_program(NOP, NOP, NOP, NOP, SRET, PARK);
    reset_core();
    _dut._csr_file._stvec.base = 30'h0000_0010;
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0020;
    _dut._csr_file._mie.stip = 1'b1;
    _dut._csr_file._mip.stip = 1'b1;

    begin
      int unsigned waits;
      waits = 0;
      while ((_dut._csr_file._scause != 32'h8000_0005) && (waits < 120)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < 120, 1'b1, "firmware STIP reaches supervisor trap handling");
    end
    expect_word(_dut._csr_file._scause, 32'h8000_0005, "supervisor timer interrupt scause");
    expect_word(_dut._csr_file._stval, 32'h0000_0000, "supervisor timer interrupt stval");
    _dut._csr_file._mip.stip = 1'b0;

    begin
      int unsigned waits;
      waits = 0;
      while (((_dut._csr_file._priv_mode != PRIV_SUPERVISOR) ||
              !(_dut._ifetch_ifu_cache.req.valid &&
                (_dut._ifetch_ifu_cache.req.addr == 32'h0000_0000))) && (waits < 300)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < 300, 1'b1, "timer sret resumes interrupted supervisor instruction");
    end

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

    _dut._csr_file._priv_mode   = PRIV_MACHINE;
    _dut._csr_file._mstatus.sie = 1'b1;
    expect_interrupt_request(1'b0, TRAP_SRC_NONE,
                             "delegated supervisor interrupt cannot preempt machine mode");

    clear_interrupt_state();
    load_program(ADDI_X1_1, LUI_X4_MMIO, LW_X2_X4, ADD_X3_X2, NOP, NOP);
    _mmio_wait = 40;
    reset_core();

    // Interrupts require machine mode + global/specific enables.
    _dut._csr_file._priv_mode = PRIV_MACHINE;
    _dut._csr_file._mstatus.mie = 1'b1;
    _dut._csr_file._mie.msip = 1'b1;

    _dut._reg_file._regs[1] = 32'h0000_0000;
    _dut._reg_file._regs[2] = 32'h0000_0000;
    _dut._reg_file._regs[3] = 32'hdead_beef;

    // Raise the interrupt at the overlap: everything older than the dependent
    // add retires, the add and everything younger is squashed.
    wait_overlap(200);
    _dut._csr_file._mip.msip = 1'b1;

    @(negedge _clk);
    _mmio_wait = 0;

    wait_trap_entry(32'h8000_0003, 200);
    expect_word(_dut._csr_file._mepc, DependentPc, "trap mepc points at dependent instruction");

    // Sanity: core should stay running (not a synthetic halt trap).
    expect_bit(_halted, 1'b0, "trap entry does not halt");

    // Older instructions retire and write back; younger dependent gets squashed.
    expect_word(_dut._reg_file._regs[1], 32'h0000_0001, "older addi committed");
    expect_word(_dut._reg_file._regs[2], LOAD_DATA, "load result committed before trap");
    expect_word(_dut._reg_file._regs[3], 32'hdead_beef, "squashed dependent add does not write x3");

    // Let a delegated supervisor software interrupt traverse the complete
    // pipeline, update supervisor CSRs, redirect to stvec, and return via sret.
    load_program(NOP, NOP, NOP, NOP, SRET, PARK);
    reset_core();
    _dut._csr_file._stvec.base = 30'h0000_0010;
    _dut._csr_file._priv_mode = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.sie = 1'b1;
    _dut._csr_file._mideleg = 32'h0000_0002;
    _dut._csr_file._mie.ssip = 1'b1;
    _dut._csr_file._mepc = 32'h1111_1110;
    _dut._csr_file._mcause = '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT};
    _dut._csr_file._mtval = 32'h2222_2222;

    _dut._csr_file._mip.ssip = 1'b1;

    begin
      int unsigned _waits;
      _waits = 0;
      while (((_dut._csr_file._scause != 32'h8000_0001) ||
              (_dut._csr_file._priv_mode != PRIV_SUPERVISOR)) && (_waits < 120)) begin
        _waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(_waits < 120, 1'b1, "delegated supervisor interrupt retires");
    end

    expect_word(_dut._csr_file._sepc, 32'h0000_0000, "supervisor interrupt sepc");
    expect_word(_dut._csr_file._scause, 32'h8000_0001, "supervisor interrupt scause");
    expect_word(_dut._csr_file._stval, 32'h0000_0000, "supervisor interrupt stval");
    expect_word(_dut._csr_file._mepc, 32'h1111_1110, "supervisor interrupt preserves mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0003, "supervisor interrupt preserves mcause");
    expect_word(_dut._csr_file._mtval, 32'h2222_2222, "supervisor interrupt preserves mtval");

    _dut._csr_file._mip.ssip = 1'b0;

    begin
      int unsigned _waits;
      _waits = 0;
      while (((_dut._csr_file._priv_mode != PRIV_SUPERVISOR) ||
              !(_dut._ifetch_ifu_cache.req.valid
                && (_dut._ifetch_ifu_cache.req.addr == 32'h0000_0000))) && (_waits < 300)) begin
        _waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(_waits < 300, 1'b1, "sret resumes interrupted supervisor instruction");
      expect_bit(_dut._csr_file._priv_mode == PRIV_SUPERVISOR, 1'b1,
                 "interrupt sret restores supervisor mode");
      expect_word(_dut._ifetch_ifu_cache.req.addr, 32'h0000_0000, "interrupt sret resumes at sepc");
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
