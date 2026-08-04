// tb_comparator.sv — self-checking testbench for the branch comparator.
//
//   make sim TB=comparator      /      just sim comparator
//
// Purely combinational: drive inputs, settle, compare. No clock.
//
// The DUT exposes eq and lt only; the six RV32I branches derive from those two
// (BNE is !eq, BGE/BGEU are !lt), so those are what gets checked.
//
// The comparator's whole job is to get signedness right, so that is what the
// vectors attack. An implementation that flips the sign bit before an unsigned
// compare -- the trick this DUT uses -- is correct, but so is a broken one on
// every operand pair where both values are small and positive. The cases that
// actually discriminate:
//
//   * MIN_INT vs MAX_INT, where signed and unsigned disagree completely
//   * 0xffffffff vs 0, which is -1 < 0 signed and 4294967295 > 0 unsigned
//   * equality on values with the top bit set, which a mis-applied flip breaks
//   * sngd toggling on identical operands, which must change lt and must
//     *not* change eq
//   * eq and lt never both true, for any input pair
//
// A comparator that passes 1 vs 2 and fails nothing else has proved nothing.

`timescale 1ns / 1ps

module tb_comparator
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 200_000;

  localparam word_t MinInt = 32'h8000_0000;  // -2147483648 signed, huge unsigned
  localparam word_t MaxInt = 32'h7fff_ffff;  // +2147483647 signed
  localparam word_t NegOne = 32'hffff_ffff;  // -1 signed, 4294967295 unsigned
  localparam word_t NegTwo = 32'hffff_fffe;

  localparam int unsigned RandomVectors = 20_000;
  localparam int unsigned RandomSeed = 32'h00c0_ffee;
  localparam int unsigned MaxPrintedFailures = 20;

  word_t         _src_a;
  word_t         _src_b;
  logic          _sngd;
  branch_flags_t _branch_flags;

  int unsigned   errors = 0;
  int unsigned   checks = 0;
  int unsigned   printed = 0;

  comparator _dut (
    .src_a(_src_a),
    .src_b(_src_b),
    .sngd(_sngd),
    .branch_flags(_branch_flags)
  );

  // ------------------------------------------------------------- helpers --

  // $display rather than $error: Verilator treats $error as $stop and aborts on
  // the first mismatch, hiding every later failure. Count here, $fatal once at
  // the end so `make sim` still exits non-zero.
  task automatic fail(input string what, input string detail);
    errors++;
    if (printed < MaxPrintedFailures) begin
      printed++;
      $display("  FAIL %-40s %s", what, detail);
    end else if (printed == MaxPrintedFailures) begin
      printed++;
      $display("  ... further failures suppressed; see the summary for exact counts");
    end
  endtask

  task automatic check(input logic sgn, input word_t a, input word_t b, input logic exp_eq,
                       input logic exp_lt, input string what);
    _sngd  = sgn;
    _src_a = a;
    _src_b = b;
    #1;
    checks++;
    if ({_branch_flags.eq, _branch_flags.lt} !== {exp_eq, exp_lt}) begin
      fail(what, $sformatf(
           "sngd=%b a=0x%08h b=0x%08h -> eq=%b lt=%b, expected eq=%b lt=%b",
           sgn,
           a,
           b,
           _branch_flags.eq,
           _branch_flags.lt,
           exp_eq,
           exp_lt
           ));
    end
    // Holds for every input pair regardless of the expected values: a value
    // cannot be both equal to and less than another. A DUT that asserts both
    // is broken even if the individual bit under test happened to match.
    if (_branch_flags.eq && _branch_flags.lt) begin
      fail(what, $sformatf("eq and lt both asserted: sngd=%b a=0x%08h b=0x%08h", sgn, a, b));
    end
  endtask

  // Shorthand for the three orderings, so the vectors below read as relations
  // rather than as bit pairs. "gt" here means the derived !eq && !lt that the
  // branch logic will use for BGE/BGEU.
  task automatic check_lt(input logic sgn, input word_t a, input word_t b, input string what);
    check(sgn, a, b, 1'b0, 1'b1, what);
  endtask

  task automatic check_gt(input logic sgn, input word_t a, input word_t b, input string what);
    check(sgn, a, b, 1'b0, 1'b0, what);
  endtask

  task automatic check_eq(input logic sgn, input word_t a, input word_t b, input string what);
    check(sgn, a, b, 1'b1, 1'b0, what);
  endtask

  // ------------------------------------------------------- reference model --

  // Deliberately built from different primitives than the DUT: a bit-by-bit
  // scan from the MSB down, with the sign bits handled as an explicit special
  // case, rather than XOR-flipping the top bit and leaning on `<`. A model that
  // reused the DUT's trick would reproduce the DUT's mistakes and agree with it
  // enthusiastically.
  //
  // Returns 2'b{eq, lt}.
  function automatic logic [1:0] ref_cmp(input logic sgn, input word_t a, input word_t b);
    // Signed: differing sign bits settle it immediately -- the negative operand
    // is the smaller one, whatever the remaining 31 bits say.
    if (sgn && (a[31] !== b[31])) return a[31] ? 2'b01 : 2'b00;

    // Otherwise (unsigned, or same sign) plain magnitude order on the raw bits
    // is correct: for two negatives, the larger two's-complement pattern is
    // also the larger signed value.
    for (int i = 31; i >= 0; i--) begin
      if (a[i] !== b[i]) return a[i] ? 2'b00 : 2'b01;
    end
    return 2'b10;
  endfunction

  // Uniform randoms almost never land on the values that break a comparator,
  // so weight the corners and the sign boundary explicitly.
  function automatic word_t rand_operand();
    case ($urandom_range(
        0, 9
    ))
      0:       return 32'h0000_0000;
      1:       return NegOne;
      2:       return MinInt;
      3:       return MaxInt;
      4:       return 32'h0000_0001;
      5:       return 32'h7fff_fffe;  // just below the sign boundary
      6:       return 32'h8000_0001;  // just above it
      7:       return 32'($urandom) & 32'h0000_00ff;  // small, both signs agree
      8:       return 32'h8000_0000 | 32'($urandom);  // sign bit always set
      default: return 32'($urandom);
    endcase
  endfunction

  // ---------------------------------------------------------------- tests --

  initial begin
    // ---- equality, both modes ---------------------------------------------
    // The MSB flip is applied to both operands, so it cancels for eq. If eq
    // ever depends on sngd, the flip is being applied to only one side.
    check_eq(1'b0, 32'd0, 32'd0, "eq 0==0 unsigned");
    check_eq(1'b1, 32'd0, 32'd0, "eq 0==0 signed");
    check_eq(1'b0, 32'h1234_5678, 32'h1234_5678, "eq equal words unsigned");
    check_eq(1'b1, 32'h1234_5678, 32'h1234_5678, "eq equal words signed");
    check_eq(1'b0, MinInt, MinInt, "eq MIN_INT==MIN_INT unsigned");
    check_eq(1'b1, MinInt, MinInt, "eq MIN_INT==MIN_INT signed");
    check_eq(1'b0, NegOne, NegOne, "eq ffffffff==ffffffff unsigned");
    check_eq(1'b1, NegOne, NegOne, "eq -1==-1 signed");
    // Differing in one bit only -- top and bottom.
    check_lt(1'b1, 32'h0000_0000, 32'h0000_0001, "eq false on LSB difference");
    check_gt(1'b1, 32'h0000_0000, MinInt, "eq false on MSB difference");

    // ---- unsigned ordering ------------------------------------------------
    check_lt(1'b0, 32'd1, 32'd2, "unsigned 1<2");
    check_gt(1'b0, 32'd2, 32'd1, "unsigned 2>1");
    check_lt(1'b0, 32'd0, NegOne, "unsigned 0 < ffffffff");
    check_gt(1'b0, NegOne, 32'd0, "unsigned ffffffff > 0");
    // Top bit set means "large", not "negative". A comparator stuck in signed
    // mode answers the opposite on both of these.
    check_gt(1'b0, MinInt, MaxInt, "unsigned 80000000 > 7fffffff");
    check_lt(1'b0, MaxInt, MinInt, "unsigned 7fffffff < 80000000");
    check_gt(1'b0, NegOne, NegTwo, "unsigned ffffffff > fffffffe");

    // ---- signed ordering --------------------------------------------------
    check_lt(1'b1, 32'd1, 32'd2, "signed 1<2");
    check_gt(1'b1, 32'd2, 32'd1, "signed 2>1");
    check_lt(1'b1, NegOne, 32'd0, "signed -1<0");
    check_gt(1'b1, 32'd0, NegOne, "signed 0>-1");
    check_lt(1'b1, NegOne, 32'd1, "signed -1<1");
    check_lt(1'b1, NegTwo, NegOne, "signed -2<-1");
    check_gt(1'b1, NegOne, NegTwo, "signed -1>-2");
    // The corner a subtract-and-test-the-sign-bit implementation gets wrong:
    // MIN_INT - MAX_INT overflows to 0x00000001, whose sign bit is 0.
    check_lt(1'b1, MinInt, MaxInt, "signed MIN_INT<MAX_INT (overflow corner)");
    check_gt(1'b1, MaxInt, MinInt, "signed MAX_INT>MIN_INT (overflow corner)");
    check_lt(1'b1, MinInt, 32'd0, "signed MIN_INT<0");
    check_lt(1'b1, MinInt, NegOne, "signed MIN_INT<-1");
    check_gt(1'b1, MaxInt, 32'd0, "signed MAX_INT>0");
    // Adjacent across the sign boundary: 0x7fffffff is the largest signed
    // value and 0x80000000 the smallest, so the ordering inverts here.
    check_gt(1'b1, 32'h7fff_ffff, 32'h8000_0000, "signed 7fffffff > 80000000");
    check_lt(1'b1, 32'h8000_0000, 32'h7fff_ffff, "signed 80000000 < 7fffffff");
    check_lt(1'b1, 32'h8000_0000, 32'h8000_0001, "signed MIN_INT < MIN_INT+1");

    // ---- the two modes must disagree --------------------------------------
    // Same operands, opposite answers. If sngd is ignored, or the two paths
    // are wired together, these pairs cannot both pass.
    check_lt(1'b1, NegOne, 32'd1, "mode split: signed   -1 < 1");
    check_gt(1'b0, NegOne, 32'd1, "mode split: unsigned -1 > 1");
    check_lt(1'b1, MinInt, MaxInt, "mode split: signed   MIN < MAX");
    check_gt(1'b0, MinInt, MaxInt, "mode split: unsigned MIN > MAX");
    check_gt(1'b1, 32'd0, MinInt, "mode split: signed   0 > 80000000");
    check_lt(1'b0, 32'd0, MinInt, "mode split: unsigned 0 < 80000000");

    // ---- both operands negative (signed) ----------------------------------
    // Same sign bit, so the flip cancels and raw magnitude order decides. This
    // is the half of signed comparison that looks unsigned.
    check_lt(1'b1, 32'hffff_ff00, 32'hffff_ff01, "signed -256 < -255");
    check_gt(1'b1, 32'hffff_ff01, 32'hffff_ff00, "signed -255 > -256");
    check_lt(1'b1, 32'h8000_0000, 32'hffff_ffff, "signed MIN_INT < -1");

    // ---- randomized cross-check against the reference model ---------------
    // Directed tests encode what the author thought to check. This layer
    // catches what nobody thought of -- in particular per-bit faults, which no
    // hand-written vector set can claim to cover.
    begin
      int unsigned       errs_before;
      logic              sgn;
      word_t             a;
      word_t             b;
      logic        [1:0] r;

      errs_before = errors;
      void'($urandom(RandomSeed));

      for (int unsigned t = 0; t < RandomVectors; t++) begin
        sgn = 1'($urandom_range(0, 1));
        a   = rand_operand();
        b   = rand_operand();
        r   = ref_cmp(sgn, a, b);
        check(sgn, a, b, r[1], r[0], $sformatf("random #%0d", t));
      end

      $display("tb_comparator: %0d random vectors vs reference model, %0d mismatches",
               RandomVectors, errors - errs_before);
    end

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_comparator: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_comparator: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_comparator: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_comparator);
    end
  end

endmodule
