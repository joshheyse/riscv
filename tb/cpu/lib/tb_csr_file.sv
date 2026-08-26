// tb_csr_file.sv - self-checking testbench for machine/supervisor CSR state.
//
//   make sim  TB=csr_file
//   make wave TB=csr_file

`timescale 1ns / 1ps

module tb_csr_file
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 10_000;

  logic        _clk;
  logic        _rst;
  logic        _csr_en;
  logic        _csr_write_en;
  csr_addr_t   _csr_addr;
  csr_data_t   _csr_write_data;
  logic        _trap_valid;
  trap_t       _trap;
  logic        _mret_valid;
  logic        _sret_valid;
  csr_data_t   _csr_read_data;
  logic        _illegal_csr;
  /* verilator lint_off UNUSEDSIGNAL */
  csr_status_t _status;
  /* verilator lint_on UNUSEDSIGNAL */

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  csr_file _dut (
    .clk(_clk),
    .rst(_rst),
    .csr_en(_csr_en),
    .csr_write_en(_csr_write_en),
    .csr_addr(_csr_addr),
    .csr_write_data(_csr_write_data),
    .trap_valid(_trap_valid),
    .trap(_trap),
    .mret_valid(_mret_valid),
    .sret_valid(_sret_valid),
    .csr_read_data(_csr_read_data),
    .illegal_csr(_illegal_csr),
    .status(_status)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bits(input logic [31:0] got, input logic [31:0] exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bool(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic tick();
    @(negedge _clk);
    @(negedge _clk);
  endtask

  task automatic drive_idle();
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
    _trap_valid = 1'b0;
    _trap = '0;
    _mret_valid = 1'b0;
    _sret_valid = 1'b0;
  endtask

  task automatic retire_sret();
    @(negedge _clk);
    _sret_valid = 1'b1;
    @(negedge _clk);
    _sret_valid = 1'b0;
  endtask

  task automatic read_csr(input logic [11:0] addr, input csr_data_t exp, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b0;
    _csr_addr.raw = addr;
    _csr_write_data = '0;
    #1;
    expect_bool(_illegal_csr, 1'b0, {what, " legal read"});
    expect_bits(_csr_read_data, exp, what);
    @(negedge _clk);
    _csr_en   = 1'b0;
    _csr_addr = '0;
  endtask

  task automatic write_csr(input logic [11:0] addr, input csr_data_t data, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr.raw = addr;
    _csr_write_data = data;
    #1;
    expect_bool(_illegal_csr, 1'b0, {what, " legal write"});
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
  endtask

  task automatic expect_illegal_read(input logic [11:0] addr, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b0;
    _csr_addr.raw = addr;
    #1;
    expect_bool(_illegal_csr, 1'b1, what);
    expect_bits(_csr_read_data, '0, {what, " data"});
    @(negedge _clk);
    _csr_en   = 1'b0;
    _csr_addr = '0;
  endtask

  task automatic expect_illegal_write(input logic [11:0] addr, input csr_data_t data,
                                      input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr.raw = addr;
    _csr_write_data = data;
    #1;
    expect_bool(_illegal_csr, 1'b1, what);
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
  endtask

  task automatic take_target_trap(input epc_t epc, input cause_t cause, input tval_t tval,
                                  input priv_mode_t target_priv);
    @(negedge _clk);
    _trap_valid = 1'b1;
    _trap = '{epc: epc, cause: cause, tval: tval, handler_pc: '0, target_priv: target_priv};
    @(negedge _clk);
    _trap_valid = 1'b0;
    _trap = '0;
  endtask

  task automatic take_trap(input epc_t epc, input cause_t cause, input tval_t tval);
    take_target_trap(epc, cause, tval, PRIV_MACHINE);
  endtask

  task automatic retire_mret();
    @(negedge _clk);
    _mret_valid = 1'b1;
    @(negedge _clk);
    _mret_valid = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_file);
    end

    drive_idle();
    _rst = 1'b1;
    repeat (2) @(negedge _clk);
    _rst = 1'b0;

    // Reset state: writable machine CSRs and read-only ID CSRs all read zero.
    read_csr(CSR_MSTATUS, 32'h0000_0000, "reset mstatus");
    read_csr(CSR_MIE, 32'h0000_0000, "reset mie");
    read_csr(CSR_MTVEC, 32'h0000_0000, "reset mtvec");
    read_csr(CSR_MEPC, 32'h0000_0000, "reset mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0000, "reset mcause");
    read_csr(CSR_MTVAL, 32'h0000_0000, "reset mtval");
    read_csr(CSR_MIP, 32'h0000_0000, "reset mip");
    read_csr(CSR_SSCRATCH, 32'h0000_0000, "reset sscratch");
    read_csr(CSR_SATP, 32'h0000_0000, "reset satp is Bare");
    read_csr(CSR_MVENDORID, 32'h0000_0000, "read mvendorid");
    read_csr(CSR_MARCHID, 32'h0000_0000, "read marchid");
    read_csr(CSR_MIMPID, 32'h0000_0000, "read mimpid");
    read_csr(CSR_MHARTID, 32'h0000_0000, "read mhartid");
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "reset privilege mode");

    // Idle cycles should not report illegal access even if the address is not
    // implemented.
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b1;
    _csr_addr.raw = 12'hfff;
    #1;
    expect_bool(_illegal_csr, 1'b0, "idle access is not illegal");
    _csr_write_en = 1'b0;

    // Normal writable CSR path.
    write_csr(CSR_MTVEC, 32'h0000_1001, "write mtvec with unsupported vectored mode");
    read_csr(CSR_MTVEC, 32'h0000_1000, "mtvec coerces mode to direct");
    expect_bits(_status.mtvec, 32'h0000_1000, "status exposes legalized mtvec");
    expect_bits(_status.mstatus, 32'h0000_0000, "status exposes mstatus");
    expect_bits(_status.mie, 32'h0000_0000, "status exposes mie");
    expect_bits(_status.mip, 32'h0000_0000, "status exposes mip");
    expect_bits(_status.mepc, 32'h0000_0000, "status exposes reset mepc");
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "status exposes reset privilege mode");

    // `sstatus` is a masked view of shared `mstatus` storage. Writes through
    // the supervisor view must preserve machine-only fields.
    write_csr(CSR_MSTATUS, 32'h0000_19aa, "seed machine and supervisor status fields");
    read_csr(CSR_SSTATUS, 32'h0000_0122, "sstatus reads supervisor fields from mstatus");
    write_csr(CSR_SSTATUS, 32'h0000_0002, "write supervisor status view");
    read_csr(CSR_MSTATUS, 32'h0000_188a, "sstatus write preserves machine status fields");
    read_csr(CSR_SSTATUS, 32'h0000_0002, "sstatus write updates shared supervisor fields");
    write_csr(CSR_MSTATUS, 32'h0000_0000, "clear status after alias checks");

    write_csr(CSR_SSTATUS, 32'h0000_0120, "seed supervisor return to supervisor");
    retire_sret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_SUPERVISOR),
                "sret restores supervisor mode from spp");
    read_csr(CSR_SSTATUS, 32'h0000_0022, "sret restores sie and clears spp");
    write_csr(CSR_SSTATUS, 32'h0000_0000, "seed supervisor return to user");
    retire_sret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_USER), "sret restores user mode");
    read_csr(CSR_SSTATUS, 32'h0000_0020, "sret sets spie and leaves spp clear");

    // Return to machine mode for the remaining machine trap checks.
    take_trap(32'h0000_0000, '{is_interrupt: 1'b0, code: CAUSE_ECALL_U}, '0);

    // Supervisor trap CSRs have independent state. `sie` and `sip` expose
    // only interrupt positions delegated by `mideleg`.
    write_csr(CSR_STVEC, 32'h0000_2001, "write stvec with unsupported vectored mode");
    read_csr(CSR_STVEC, 32'h0000_2000, "stvec coerces mode to direct");
    write_csr(CSR_SEPC, 32'h0000_0080, "write sepc");
    read_csr(CSR_SEPC, 32'h0000_0080, "read sepc");
    write_csr(CSR_SCAUSE, 32'h8000_0009, "write scause");
    read_csr(CSR_SCAUSE, 32'h8000_0009, "read scause");
    write_csr(CSR_STVAL, 32'hdead_beef, "write stval");
    read_csr(CSR_STVAL, 32'hdead_beef, "read stval");
    write_csr(CSR_SSCRATCH, 32'hcafe_babe, "write sscratch");
    read_csr(CSR_SSCRATCH, 32'hcafe_babe, "read sscratch");
    write_csr(CSR_MEDELEG, 32'h0000_0100, "write medeleg");
    read_csr(CSR_MEDELEG, 32'h0000_0100, "read medeleg");
    write_csr(CSR_MEDELEG, 32'hffff_ffff, "write all medeleg bits");
    read_csr(CSR_MEDELEG, 32'h0000_b35d,
             "medeleg keeps implemented exceptions including page faults");
    write_csr(CSR_MEDELEG, 32'h0000_0100, "restore user ecall delegation");
    write_csr(CSR_MIDELEG, 32'h0000_0222, "delegate supervisor interrupt positions");
    read_csr(CSR_MIDELEG, 32'h0000_0222, "read mideleg");
    write_csr(CSR_MIE, 32'h0000_0aaa, "seed machine and supervisor enables");
    read_csr(CSR_SIE, 32'h0000_0222, "sie exposes delegated enables");
    write_csr(CSR_SIE, 32'h0000_0020, "write sie view");
    read_csr(CSR_MIE, 32'h0000_08a8, "sie write preserves machine interrupt enables");
    write_csr(CSR_MIP, 32'h0000_0aaa, "seed machine and supervisor pending bits");
    read_csr(CSR_SIP, 32'h0000_0222, "sip exposes delegated pending bits");
    write_csr(CSR_SIP, 32'h0000_0002, "write sip view");
    read_csr(CSR_MIP, 32'h0000_088a, "sip write preserves machine pending bits");

    write_csr(CSR_MEPC, 32'h0000_0040, "write mepc");
    read_csr(CSR_MEPC, 32'h0000_0040, "read mepc");
    expect_bits(_status.mepc, 32'h0000_0040, "status exposes written mepc");

    write_csr(CSR_MCAUSE, 32'h8000_0007, "write mcause");
    read_csr(CSR_MCAUSE, 32'h8000_0007, "read mcause");

    write_csr(CSR_MTVAL, 32'hdead_beef, "write mtval");
    read_csr(CSR_MTVAL, 32'hdead_beef, "read mtval");

    write_csr(CSR_MIP, 32'h0000_0888, "write mip");
    read_csr(CSR_MIP, 32'h0000_0888, "read mip");

    write_csr(CSR_MSTATUS, 32'hffff_ffff, "write all mstatus bits");
    read_csr(CSR_MSTATUS, 32'h0050_19aa, "mstatus keeps only supported fields");
    expect_bool(_status.mstatus.tsr, 1'b1, "status exposes written tsr");
    expect_bool(_status.mstatus.tvm, 1'b1, "status exposes written tvm");

    write_csr(CSR_MSTATUS, 32'h0040_0000, "write tsr only");
    read_csr(CSR_MSTATUS, 32'h0040_0000, "mstatus preserves tsr bit");
    expect_bool(_status.mstatus.tsr, 1'b1, "status exposes tsr-only write");

    write_csr(CSR_MSTATUS, 32'h0000_1000, "write invalid mpp encoding");
    read_csr(CSR_MSTATUS, 32'h0000_1800, "invalid mpp coerces to machine");
    retire_mret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "mret after invalid mpp stays machine");
    read_csr(CSR_MSTATUS, 32'h0000_0080, "mret clears legalized mpp");

    // `satp` stores both RV32-defined translation modes and the root PPN. ASIDs
    // are hardwired to zero until the TLB can use them to tag translations.
    write_csr(CSR_SATP, 32'h0000_0000, "write Bare satp");
    read_csr(CSR_SATP, 32'h0000_0000, "Bare satp remains zero");
    write_csr(CSR_SATP, 32'h8048_d159, "write Sv32 satp");
    read_csr(CSR_SATP, 32'h8008_d159, "read Sv32 satp with ASID cleared");
    expect_bits(word_t'(_status.satp), 32'h8008_d159, "status exposes legalized Sv32 satp");
    write_csr(CSR_SATP, 32'hffff_ffff, "write all satp bits");
    read_csr(CSR_SATP, 32'h803f_ffff, "mode and PPN retained while ASID is cleared");
    expect_bits(word_t'(_status.satp), 32'h803f_ffff, "status exposes legalized satp fields");

    // Unknown CSRs and read-only ID writes should be illegal.
    expect_illegal_read(12'hfff, "unknown CSR read illegal");
    expect_illegal_write(12'hfff, 32'h1234_5678, "unknown CSR write illegal");
    expect_illegal_write(CSR_MVENDORID, 32'hffff_ffff, "mvendorid write illegal");
    read_csr(CSR_MVENDORID, 32'h0000_0000, "mvendorid unchanged after write");

    // Trap entry updates trap CSRs.
    write_csr(CSR_MSTATUS, 32'h0000_0008, "seed mstatus before trap");
    take_trap(32'h0000_0080, '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR}, 32'h0000_0013);
    read_csr(CSR_MEPC, 32'h0000_0080, "trap writes mepc");
    expect_bits(_status.mepc, 32'h0000_0080, "status exposes trap mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0002, "trap writes mcause");
    read_csr(CSR_MTVAL, 32'h0000_0013, "trap writes mtval");
    read_csr(CSR_MSTATUS, 32'h0000_1880, "trap updates mstatus");
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "trap enters machine mode");

    retire_mret();
    read_csr(CSR_MSTATUS, 32'h0000_0088, "mret restores mstatus");
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "mret restores machine mode");

    write_csr(CSR_MSTATUS, 32'h0000_0800, "seed supervisor mpp before mret");
    retire_mret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_SUPERVISOR), "mret restores supervisor mode");
    read_csr(CSR_MSTATUS, 32'h0000_0080, "mret clears mpp after supervisor return");

    take_trap(32'h0000_0090, '{is_interrupt: 1'b0, code: CAUSE_ECALL_S}, 32'h0000_0000);
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE), "supervisor trap enters machine mode");
    read_csr(CSR_MSTATUS, 32'h0000_0800, "supervisor trap saves mpp");

    // A supervisor-targeted trap saves supervisor trap state and stacks the
    // supervisor interrupt-enable state without disturbing machine trap CSRs.
    write_csr(CSR_MEPC, 32'h1111_1110, "seed mepc before supervisor trap");
    write_csr(CSR_MCAUSE, 32'h0000_0003, "seed mcause before supervisor trap");
    write_csr(CSR_MTVAL, 32'h2222_2222, "seed mtval before supervisor trap");
    write_csr(CSR_MSTATUS, 32'h0000_0102, "seed user-to-supervisor trap status");
    retire_mret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_USER), "mret enters user before delegated trap");
    take_target_trap(32'h0000_0200, '{is_interrupt: 1'b0, code: CAUSE_ILLEGAL_INSTR},
                     32'hdead_beef, PRIV_SUPERVISOR);
    expect_bits(32'(_status.priv_mode), 32'(PRIV_SUPERVISOR), "user trap enters supervisor mode");
    read_csr(CSR_SEPC, 32'h0000_0200, "user trap writes sepc");
    read_csr(CSR_SCAUSE, 32'h0000_0002, "user trap writes scause");
    read_csr(CSR_STVAL, 32'hdead_beef, "user trap writes stval");
    read_csr(CSR_SSTATUS, 32'h0000_0020, "user trap stacks sie and clears spp");
    read_csr(CSR_MEPC, 32'h1111_1110, "supervisor trap preserves mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0003, "supervisor trap preserves mcause");
    read_csr(CSR_MTVAL, 32'h2222_2222, "supervisor trap preserves mtval");
    read_csr(CSR_SSCRATCH, 32'hcafe_babe, "supervisor trap preserves sscratch");

    retire_sret();
    read_csr(CSR_SSCRATCH, 32'hcafe_babe, "sret preserves sscratch");

    // An S-to-S trap records S in SPP and also replaces the prior supervisor
    // trap values without touching the machine trap state.
    take_trap(32'h0000_0300, '{is_interrupt: 1'b0, code: CAUSE_ECALL_U}, '0);
    write_csr(CSR_MSTATUS, 32'h0000_0820, "seed supervisor-to-supervisor trap status");
    retire_mret();
    expect_bits(32'(_status.priv_mode), 32'(PRIV_SUPERVISOR),
                "mret enters supervisor before delegated trap");
    take_target_trap(32'h0000_0240, '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT}, 32'h0000_0240,
                     PRIV_SUPERVISOR);
    expect_bits(32'(_status.priv_mode), 32'(PRIV_SUPERVISOR),
                "supervisor trap remains in supervisor mode");
    read_csr(CSR_SEPC, 32'h0000_0240, "supervisor trap writes sepc");
    read_csr(CSR_SCAUSE, 32'h0000_0003, "supervisor trap writes scause");
    read_csr(CSR_STVAL, 32'h0000_0240, "supervisor trap writes stval");
    read_csr(CSR_SSTATUS, 32'h0000_0100, "supervisor trap clears spie and sets spp");

    // Unsupported target encodings defensively take the machine trap path.
    take_target_trap(32'h0000_0280, '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT}, 32'h0000_00cc,
                     priv_mode_t'(2'b10));
    expect_bits(32'(_status.priv_mode), 32'(PRIV_MACHINE),
                "reserved trap target falls back to machine mode");
    read_csr(CSR_MEPC, 32'h0000_0280, "fallback trap writes mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0003, "fallback trap writes mcause");
    read_csr(CSR_MTVAL, 32'h0000_00cc, "fallback trap writes mtval");
    read_csr(CSR_MSTATUS, 32'h0000_0900, "fallback trap saves supervisor origin in mpp");

    // Trap entry wins over a simultaneous normal CSR write.
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr.raw = CSR_MEPC;
    _csr_write_data = 32'hffff_ffff;
    _trap_valid = 1'b1;
    _trap.epc = 32'h0000_00c0;
    _trap.cause = '{is_interrupt: 1'b0, code: CAUSE_BREAKPOINT};
    _trap.tval = 32'h0000_00cc;
    _trap.target_priv = PRIV_MACHINE;
    #1;
    expect_bool(_illegal_csr, 1'b0, "simultaneous trap/write legal CSR address");
    @(negedge _clk);
    drive_idle();
    read_csr(CSR_MEPC, 32'h0000_00c0, "trap wins over csr write mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0003, "trap wins over csr write mcause");
    read_csr(CSR_MTVAL, 32'h0000_00cc, "trap wins over csr write mtval");

    if (_errors == 0) begin
      $display("tb_csr_file: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_csr_file: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_csr_file: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
