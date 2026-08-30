// tb_core_system_trap.sv - SYSTEM instruction trap checks for pipelined core.
//
//   make sim DESIGN=pipelined TB=core_system_trap
//   make wave DESIGN=pipelined TB=core_system_trap

`timescale 1ns / 1ps

module tb_core_system_trap
  import riscv_pkg::*;
  import pipelined_pkg::*;
  import pmp_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1200;

  localparam instr_t ECALL = 32'h0000_0073;
  localparam instr_t EBREAK = 32'h0010_0073;
  localparam instr_t MRET = 32'h3020_0073;
  localparam instr_t SRET = 32'h1020_0073;
  localparam instr_t WFI = 32'h1050_0073;
  localparam instr_t ADDI_X1_1 = 32'h0010_0093;
  localparam instr_t PARK = 32'h0000_0063;

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
  int unsigned _waits;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .time_value('0),
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

  // Fill the whole window so every fetch, including the one after the trap
  // redirects back to zero, returns the instruction under test.
  task automatic load_instr(input instr_t instr);
    for (int unsigned word_idx = 0; word_idx < 16; word_idx++) begin
      _bus._store[word_idx] = instr;
    end
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
    _dut._csr_file._pmp.addr[0] = '1;
    _dut._csr_file._pmp.cfg[0] = '{
        locked: 1'b0,
        reserved: '0,
        addr_match: PMP_ADDR_NAPOT,
        execute: 1'b1,
        write: 1'b1,
        read: 1'b1
    };
    _dut._csr_file._pmp_decoder._regions = pmp_decode_regions(_dut._csr_file._pmp);
  endtask

  // Advance until the instruction under test is sitting in IF/ID, where the
  // decode-stage trap checks below expect it. Waiting on the event rather than
  // counting cycles keeps this independent of L1 bypass latency.
  task automatic issue_first_instr(input instr_t instr, input string what);
    _waits = 0;
    while (!(_dut._ifetch_ifu_cache.req.valid
             && _dut._ifetch_ifu_cache.req.addr == 32'h0000_0000) && _waits < 20) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._ifetch_ifu_cache.req.valid, 1'b1, {what, " fetch request valid"});
    expect_word(_dut._ifetch_ifu_cache.req.addr, 32'h0000_0000, {what, " fetch request pc"});

    _waits = 0;
    while (!(_dut._fetched.valid && _dut._fetched.slot.instr.raw == instr) && _waits < 60) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
    expect_bit(_dut._fetched.valid, 1'b1, {what, " fetched valid"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " fetched instr"});

    _waits = 0;
    while (!(_dut._if_id.valid && _dut._if_id.slot.instr.raw == instr) && _waits < 60) begin
      _waits++;
      @(posedge _clk);
      #1;
    end
  endtask

  task automatic check_system_trap(input instr_t instr, input trap_src_e src, input word_t mcause,
                                   input string what);
    load_instr(instr);
    reset_core();
    issue_first_instr(instr, what);

    expect_bit(_dut._if_id.valid, 1'b1, {what, " IF/ID valid"});
    expect_word(_dut._if_id.slot.instr.raw, instr, {what, " IF/ID instr"});
    expect_bit(_dut._ctrl.trap.valid, 1'b1, {what, " decoded trap valid"});
    expect_word(32'(_dut._ctrl.trap.src), 32'(src), {what, " decoded trap src"});
    expect_bit(_dut._id_trap.valid, 1'b1, {what, " trap valid"});
    expect_word(_dut._id_trap.payload.epc, 32'h0000_0000, {what, " trap epc"});
    expect_word(_dut._id_trap.payload.cause, mcause, {what, " trap cause"});
    expect_word(_dut._id_trap.payload.tval, 32'h0000_0000, {what, " trap tval"});
  endtask

  task automatic check_mret_privilege_trap(input priv_mode_e priv_mode, input string what);
    int unsigned waits;

    load_instr(MRET);
    reset_core();
    _dut._csr_file._priv_mode = priv_mode;
    issue_first_instr(MRET, what);

    waits = 0;
    while ((_dut._csr_file._mcause != 32'h0000_0002) && (waits < 40)) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(waits < 40, 1'b1, {what, " trap retired"});
    expect_bit(_halted, 1'b0, {what, " trap entry does not halt"});
    expect_word(_dut._csr_file._mepc, 32'h0000_0000, {what, " mepc"});
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, {what, " mcause"});
    expect_word(_dut._csr_file._mtval, MRET, {what, " mtval"});
  endtask

  task automatic check_tsr_sret_trap();
    int unsigned waits;

    load_instr(SRET);
    reset_core();
    _dut._csr_file._priv_mode   = PRIV_SUPERVISOR;
    _dut._csr_file._mstatus.tsr = 1'b1;
    issue_first_instr(SRET, "supervisor sret with tsr");

    waits = 0;
    while ((_dut._csr_file._mcause != 32'h0000_0002) && (waits < 40)) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(waits < 40, 1'b1, "tsr-blocked sret trap retired");
    expect_word(_dut._csr_file._mepc, 32'h0000_0000, "tsr-blocked sret mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0002, "tsr-blocked sret mcause");
    expect_word(_dut._csr_file._mtval, SRET, "tsr-blocked sret mtval");
    expect_bit(_dut._csr_file._priv_mode == PRIV_MACHINE, 1'b1,
               "tsr-blocked sret enters machine mode");
  endtask

  task automatic check_wfi_nop(input priv_mode_e priv_mode, input string what);
    int unsigned waits;

    for (int unsigned word_idx = 0; word_idx < 16; word_idx++) begin
      _bus._store[word_idx] = PARK;
    end
    _bus._store[0] = WFI;
    _bus._store[1] = ADDI_X1_1;
    reset_core();
    _dut._csr_file._priv_mode = priv_mode;
    _dut._reg_file._regs[1] = '0;

    waits = 0;
    while ((_dut._reg_file._regs[1] != 32'h0000_0001) && (waits < 100)) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(waits < 100, 1'b1, {what, " resumes at pc+4"});
    expect_word(_dut._csr_file._mcause, '0, {what, " does not trap"});
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_system_trap);
    end

    _rst = 1'b1;

    check_system_trap(ECALL, TRAP_SRC_ECALL, 32'h0000_000b, "ecall");
    check_system_trap(EBREAK, TRAP_SRC_EBREAK, 32'h0000_0003, "ebreak");
    check_mret_privilege_trap(PRIV_SUPERVISOR, "supervisor mret");
    check_mret_privilege_trap(PRIV_USER, "user mret");
    check_tsr_sret_trap();
    check_wfi_nop(PRIV_MACHINE, "machine WFI no-op");
    check_wfi_nop(PRIV_SUPERVISOR, "supervisor WFI no-op");
    check_wfi_nop(PRIV_USER, "user WFI immediate completion");

    if (_errors == 0) begin
      $display("tb_core_system_trap: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_system_trap: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_system_trap: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
