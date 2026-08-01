// tb_extend.sv — self-checking testbench for the immediate-extend unit.
//
//   make sim TB=extend      /      just sim extend
//
// Every vector below is a real instruction encoding produced by
// riscv64-none-elf-as (-march=rv32i -mabi=ilp32), not a hand-computed one, so
// the expected immediates are checked against the toolchain's reading of the
// ISA rather than against this file's author. Regenerate with:
//
//   riscv64-none-elf-as -march=rv32i -mabi=ilp32 t.S -o t.o
//   riscv64-none-elf-objdump -d -M no-aliases t.o
//
// Branch and jump immediates are PC-relative, so the expected value is
// (target - pc) taken from the disassembly listing.

`timescale 1ns / 1ps

module tb_extend
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  // Held as a full 32-bit encoding so the vectors below match objdump output
  // verbatim; only [31:7] is wired to the DUT, so the opcode bits are unread.
  /* verilator lint_off UNUSEDSIGNAL */
  logic        [31:0] _instr;
  /* verilator lint_on UNUSEDSIGNAL */
  imm_src_t           _imm_src;
  word_t              _imm_ext;

  int unsigned        errors = 0;
  int unsigned        checks = 0;

  // extend only takes instr[31:7]; the opcode is decoded elsewhere.
  extend _dut (
    .imm_src(_imm_src),
    .instr  (_instr[31:7]),
    .imm_ext(_imm_ext)
  );

  // ------------------------------------------------------------- helpers --

  task automatic check(input logic [31:0] encoding, input imm_src_t src, input logic [31:0] exp,
                       input string what);
    _instr   = encoding;
    _imm_src = src;
    #1;
    checks++;
    if (_imm_ext !== exp) begin
      errors++;
      // $display, not $error: Verilator treats $error as $stop and aborts the
      // run on the first mismatch, which hides every later failure. Counting
      // here and calling $fatal once at the end reports the whole picture.
      $display("  FAIL %s: instr=0x%08h -> imm_ext=0x%08h, expected 0x%08h", what, encoding,
               _imm_ext, exp);
    end
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    // ---- I-type: addi / lw ------------------------------------------------
    check(32'h00158513, IMM_I, 32'h0000_0001, "I  addi a0,a1,1");
    check(32'hfff58513, IMM_I, 32'hffff_ffff, "I  addi a0,a1,-1");
    check(32'h7ff58513, IMM_I, 32'h0000_07ff, "I  addi a0,a1,2047   (max positive)");
    check(32'h80058513, IMM_I, 32'hffff_f800, "I  addi a0,a1,-2048  (min negative)");
    check(32'h0645a503, IMM_I, 32'h0000_0064, "I  lw   a0,100(a1)");
    check(32'hffc5a503, IMM_I, 32'hffff_fffc, "I  lw   a0,-4(a1)");

    // ---- S-type: sw -------------------------------------------------------
    // Same 12-bit value as I-type, but split across instr[31:25] and
    // instr[11:7]. A reassembly bug shows up here and nowhere else.
    check(32'h06a5a223, IMM_S, 32'h0000_0064, "S  sw   a0,100(a1)");
    check(32'hfea5ae23, IMM_S, 32'hffff_fffc, "S  sw   a0,-4(a1)");
    check(32'h7ea5afa3, IMM_S, 32'h0000_07ff, "S  sw   a0,2047(a1)  (max positive)");
    check(32'h80a5a023, IMM_S, 32'hffff_f800, "S  sw   a0,-2048(a1) (min negative)");

    // ---- B-type: branches -------------------------------------------------
    // 13-bit, implicit zero in bit 0, bits scrambled across four fields.
    check(32'h00b50063, IMM_B, 32'h0000_0000, "B  beq -> +0   (self)");
    check(32'h00b50e63, IMM_B, 32'h0000_001c, "B  beq -> +28  (forward)");
    check(32'h00b51c63, IMM_B, 32'h0000_0018, "B  bne -> +24  (forward)");
    // Large offsets are essential here: with small ones the upper immediate
    // fields are all zero, so permuting them is undetectable. These set
    // imm[11] (which comes from instr[7]) and imm[10:5].
    check(32'h7cb50ce3, IMM_B, 32'h0000_0fd8, "B  beq -> +4056 (large forward)");
    check(32'h7cb51ae3, IMM_B, 32'h0000_0fd4, "B  bne -> +4052 (large forward)");
    check(32'h80b504e3, IMM_B, 32'hffff_f808, "B  beq -> -2040 (large backward)");

    // ---- J-type: jal ------------------------------------------------------
    // 21-bit, implicit zero in bit 0, different scrambling again.
    check(32'hff5ff0ef, IMM_J, 32'hffff_fff4, "J  jal -> -12   (backward)");
    check(32'h010000ef, IMM_J, 32'h0000_0010, "J  jal -> +16   (forward)");
    // Same reasoning: these set imm[19:12] and imm[11], which come from
    // instr[19:12] and instr[20] respectively.
    check(32'h7d1000ef, IMM_J, 32'h0000_0fd0, "J  jal -> +4048 (large forward)");
    check(32'h7d5010ef, IMM_J, 32'h0000_1fd4, "J  jal -> +8148 (sets imm[12])");
    check(32'h805ff0ef, IMM_J, 32'hffff_f804, "J  jal -> -2044 (large backward)");

    // ---- U-type: lui / auipc ----------------------------------------------
    // NOT sign-extended: the 20 bits land in [31:12] with zeros below.
    check(32'h12345537, IMM_U, 32'h1234_5000, "U  lui   a0,0x12345");
    check(32'hfffff537, IMM_U, 32'hffff_f000, "U  lui   a0,0xfffff  (top bit set)");
    check(32'h00001517, IMM_U, 32'h0000_1000, "U  auipc a0,0x1");

    // ---- cross-check: the same encoding read as different formats ---------
    // Guards against a format being wired to the wrong branch of the case.
    check(32'hfff58513, IMM_I, 32'hffff_ffff, "X  addi -1 as I-type");
    check(32'hfff58513, IMM_U, 32'hfff5_8000, "X  same bits as U-type differ");

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_extend: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_extend: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_extend: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_extend);
    end
  end

endmodule
