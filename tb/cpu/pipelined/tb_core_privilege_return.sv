// tb_core_privilege_return.sv - end-to-end privilege trap/return on pipelined core.
//
//   make sim DESIGN=pipelined TB=core_privilege_return
//   make wave DESIGN=pipelined TB=core_privilege_return

`timescale 1ns / 1ps

module tb_core_privilege_return
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 4000;
  localparam int unsigned ReqTimeout = 128;
  localparam int unsigned TrapTimeout = 512;
  localparam int unsigned PrivReturnWait = 128;

  localparam logic [29:0] MTVEC_HANDLER_BASE = 30'h10;  // byte address 0x0000_0040

  localparam instr_t ECALL = 32'h0000_0073;
  localparam instr_t MRET = 32'h3020_0073;
  localparam instr_t SRET = 32'h1020_0073;
  localparam instr_t ILLEGAL = 32'h0000_0000;
  localparam instr_t ADDI_X3_1 = 32'h0010_0193;
  localparam instr_t ADDI_X5_8 = 32'h0080_0293;
  localparam instr_t ADDI_X2_2 = 32'h0020_0113;
  localparam instr_t NOP = 32'h0000_0013;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  mem_if _ibus ();
  mem_if _dbus ();
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
    .ibus(_ibus),
    .dbus(_dbus),
    .irq(_irq)
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
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;
    #1;
  endtask

  task automatic wait_fetch_req(input pc_t exp_addr, input string what);
    int unsigned waits;

    waits = 0;
    #1;
    while (!(_ibus.req.valid && (_ibus.req.addr == exp_addr)) && (waits < ReqTimeout)) begin
      @(negedge _clk);
      waits++;
      @(posedge _clk);
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
    _ibus.rsp.read_data = instr;

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
    _ibus.rsp.read_data = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b0, {what, " speculative response ignored on squash"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic complete_outstanding_fetch(input pc_t exp_addr, input instr_t instr,
                                            input string what);
    int unsigned waits;

    waits = 0;
    while (!(_dut._ifu._request_valid && (_dut._ifu._request_pc == exp_addr)) &&
           (waits < ReqTimeout)) begin
      @(negedge _clk);
      waits++;
    end

    expect_bit(_dut._ifu._request_valid, 1'b1, {what, " request outstanding"});
    expect_word(_dut._ifu._request_pc, exp_addr, {what, " request addr"});

    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.read_data = instr;

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, {what, " response captured"});
    expect_word(_dut._fetched.slot.pc, exp_addr, {what, " response pc"});
    expect_word(_dut._fetched.slot.instr.raw, instr, {what, " response instr"});

    @(negedge _clk);
    _ibus.rsp = '0;
  endtask

  task automatic wait_for_user_privilege_after_mret(input string what);
    int unsigned waits;

    waits = 0;
    while ((_dut._csr_file._priv_mode != PRIV_USER) && waits < PrivReturnWait) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(waits < 40, 1'b1, what);
    expect_bit(_dut._csr_file._priv_mode == PRIV_USER, 1'b1, what);
  endtask

  task automatic wait_for_trap_entry(input priv_mode_t expect_priv_mode, input word_t expect_cause,
                                     input int unsigned max_waits, input string what);
    int unsigned waits;

    waits = 0;
    while (((_dut._csr_file._mcause != expect_cause) || (_dut._csr_file._priv_mode != expect_priv_mode)) && (waits < max_waits)) begin
      waits++;
      @(posedge _clk);
      #1;
    end

    expect_bit(waits < max_waits, 1'b1, what);
    expect_bit(_dut._csr_file._mcause == expect_cause, 1'b1, {what, " mcause"});
    expect_bit(_dut._csr_file._priv_mode == expect_priv_mode, 1'b1, {what, " priv mode"});
  endtask

  task automatic verify_resume_executes_after_mret(input string what);
    complete_outstanding_fetch(32'h0000_0008, ADDI_X2_2, {what, " resume instruction"});
    fetch_instr(32'h0000_000C, NOP, {what, " following instruction"});
    begin
      int unsigned waits;
      waits = 0;
      while ((_dut._reg_file._regs[2] !== 32'h0000_0002) && (waits < 16)) begin
        @(posedge _clk);
        #1;
        waits++;
      end
      expect_bit(waits < 16, 1'b1, {what, " resume writes x2"});
      expect_word(_dut._reg_file._regs[2], 32'h0000_0002, {what, " resume executes and updates x2"
                  });
    end
  endtask

  initial begin
    if ($test$plusargs("dbg_priv")) begin
      $display(
          "time pc fetch_en flow_action trap_in_flight if_id_valid id_ex_valid _if_id.pc _fetched.valid _fetched.slot.pc mem_wb_trap _trap.valid _retire_mret priv_mode mepc");
    end

    /* verilator lint_off SYNCASYNCNET */
    $monitor("%0t %0h %0d %0d %0d %0d %0h %0d %0h %0d %0h", $time, _pc, _dut._pipe_ctrl.fetch,
             _dut._flow.action, _dut._trap_in_flight, _dut._if_id.valid, _dut._if_id.slot.pc,
             _dut._fetched.valid, _dut._fetched.slot.pc, _dut._mem_wb.trap.valid,
             _dut._csr_status.priv_mode);
    /* verilator lint_on SYNCASYNCNET */

    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_privilege_return);
    end

    _rst = 1'b1;
    drive_idle();
    reset_core();

    _dut._csr_file._mtvec.base = MTVEC_HANDLER_BASE;
    _dut._csr_file._priv_mode = PRIV_USER;
    _dut._reg_file._regs[2] = '0;
    _dut._reg_file._regs[3] = '0;
    _dut._reg_file._regs[5] = '0;

    fetch_instr(32'h0000_0000, ECALL, "ecall from user");
    offer_squashed_instr(32'h0000_0004, ADDI_X2_2, "younger user instruction is squashed");

    wait_for_trap_entry(PRIV_MACHINE, 32'h0000_0008, TrapTimeout, "trap entered machine on ecall");

    expect_word(_dut._csr_file._mepc, 32'h0000_0000, "trap mepc points at ecall");
    expect_word(_dut._csr_file._mcause, 32'h0000_0008, "trap cause is ecall from user");
    expect_bit(_dut._csr_file._priv_mode == PRIV_MACHINE, 1'b1, "trap entered machine mode");

    fetch_instr(32'h0000_0040, ADDI_X3_1, "handler writes x3");
    fetch_instr(32'h0000_0044, ADDI_X5_8, "handler loads user resume PC");
    fetch_instr(32'h0000_0048, csr_instr(CSR_MEPC, 5'd5, SYS_F3_RW, 5'd0), "handler rewrites mepc");
    fetch_instr(32'h0000_004C, MRET, "handler returns with mret");
    fetch_instr(32'h0000_0050, ILLEGAL, "younger illegal instruction after mret");

    verify_resume_executes_after_mret("core privilege return");
    wait_for_user_privilege_after_mret("mret returns to user mode");

    expect_word(_dut._csr_file._mepc, 32'h0000_0008, "handler prepared user resume PC");
    expect_word(_dut._reg_file._regs[3], 32'h0000_0001, "handler executed");
    expect_word(_dut._reg_file._regs[5], 32'h0000_0008, "handler loaded resume PC");
    expect_bit(_dut._csr_file._priv_mode == PRIV_USER, 1'b1, "privilege returned to user");

    // Repeat the complete path with exception delegation to supervisor mode.
    reset_core();
    _dut._csr_file._stvec.base = MTVEC_HANDLER_BASE;
    _dut._csr_file._medeleg = 32'h0000_0004;
    _dut._csr_file._priv_mode = PRIV_USER;
    _dut._reg_file._regs[2] = '0;
    _dut._reg_file._regs[5] = '0;
    _dut._csr_file._mepc = 32'h1111_1110;
    _dut._csr_file._mcause = '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT};
    _dut._csr_file._mtval = 32'h2222_2222;

    fetch_instr(32'h0000_0000, ILLEGAL, "delegated illegal instruction from user");
    offer_squashed_instr(32'h0000_0004, ADDI_X2_2,
                         "younger instruction after delegated trap is squashed");

    begin
      int unsigned waits;
      waits = 0;
      while (((_dut._csr_file._scause != 32'h0000_0002) ||
              (_dut._csr_file._priv_mode != PRIV_SUPERVISOR)) && (waits < TrapTimeout)) begin
        waits++;
        @(posedge _clk);
        #1;
      end
      expect_bit(waits < TrapTimeout, 1'b1, "delegated exception enters supervisor mode");
    end

    expect_word(_dut._csr_file._sepc, 32'h0000_0000, "delegated trap sepc");
    expect_word(_dut._csr_file._scause, 32'h0000_0002, "delegated trap scause");
    expect_word(_dut._csr_file._stval, ILLEGAL, "delegated trap stval");
    expect_word(_dut._csr_file._mepc, 32'h1111_1110, "delegated trap preserves mepc");
    expect_word(_dut._csr_file._mcause, 32'h0000_0003, "delegated trap preserves mcause");
    expect_word(_dut._csr_file._mtval, 32'h2222_2222, "delegated trap preserves mtval");

    fetch_instr(32'h0000_0040, ADDI_X5_8, "supervisor handler loads resume PC");
    fetch_instr(32'h0000_0044, csr_instr(CSR_SEPC, 5'd5, SYS_F3_RW, 5'd0),
                "supervisor handler rewrites sepc");
    fetch_instr(32'h0000_0048, SRET, "supervisor handler returns with sret");
    fetch_instr(32'h0000_004c, ILLEGAL, "younger illegal instruction after sret");

    verify_resume_executes_after_mret("delegated supervisor return");
    wait_for_user_privilege_after_mret("sret returns to user mode");
    expect_word(_dut._csr_file._sepc, 32'h0000_0008, "handler prepared user sepc");
    expect_bit(_dut._csr_file._priv_mode == PRIV_USER, 1'b1,
               "supervisor privilege returned to user");

    if (_errors == 0) begin
      $display("tb_core_privilege_return: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_core_privilege_return: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_privilege_return: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
