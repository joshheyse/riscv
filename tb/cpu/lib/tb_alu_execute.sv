// tb_alu_execute.sv — self-checking testbench for the RV32I ALU.
//
//   make sim TB=alu_execute      /      just sim alu_execute
//
// The ALU is purely combinational, so every check is: drive inputs, let them
// settle, compare. No clock.
//
// The vectors below concentrate on the places where a plausible-looking
// implementation is wrong:
//
//   * shift amounts above 31, which RV32I mandates be taken modulo 32
//   * SRA sign-fill, which needs a *signed* left operand and silently
//     degrades to SRL if the signedness is lost
//   * SLT at MIN_INT/MAX_INT, where a subtract-and-test-the-sign-bit
//     implementation overflows and reports the opposite answer
//   * SLTU on values with the top bit set, where a signed comparator
//     reports the opposite answer
//   * sub_arith being consulted by operations that have no variant
//
// A version of this ALU that passes ADD/AND/OR/XOR and fails nothing else is
// not a working ALU; those five are the easy half.

`timescale 1ns / 1ps

module tb_alu_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 200_000;

  localparam logic [31:0] MinInt = 32'h8000_0000;  // -2147483648
  localparam logic [31:0] MaxInt = 32'h7fff_ffff;  // +2147483647
  localparam logic [31:0] NegOne = 32'hffff_ffff;

  // Randomized cross-check against the reference model at the bottom of this
  // file. Fixed seed so a failure reproduces exactly.
  localparam int unsigned RandomVectors = 20_000;
  localparam int unsigned RandomSeed = 32'h00c0_ffee;
  // A broken DUT can fail thousands of random vectors; print enough to
  // diagnose, then stop flooding the log. The counts in the summary are exact
  // regardless.
  localparam int unsigned MaxPrintedFailures = 20;

  word_t       _src_a;
  word_t       _src_b;
  alu_ctrl_t   _ctrl;
  word_t       _alu_result;

  int unsigned errors = 0;
  int unsigned checks = 0;
  int unsigned printed = 0;

  alu_execute _dut (
    .src_a(_src_a),
    .src_b(_src_b),
    .ctrl(_ctrl),
    .alu_result(_alu_result)
  );

  // ------------------------------------------------------------- helpers --

  // $display rather than $error: Verilator treats $error as $stop and aborts
  // on the first mismatch, which hides every later failure. Count here, and
  // call $fatal once at the end so `make sim` still exits non-zero.
  task automatic check(input alu_op_e sel, input logic sa, input word_t a, input word_t b,
                       input word_t exp, input string what);
    _ctrl.op        = sel;
    _ctrl.sub_arith = sa;
    _src_a     = a;
    _src_b     = b;
    #1;
    checks++;
    if (_alu_result !== exp) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL %-34s a=0x%08h b=0x%08h sub_arith=%b -> 0x%08h, expected 0x%08h", what, a,
                 b, sa, _alu_result, exp);
      end else if (printed == MaxPrintedFailures) begin
        printed++;
        $display("  ... further failures suppressed; see the summary for exact counts");
      end
    end
  endtask

  // ------------------------------------------------------- reference model --

  // Built deliberately from *different* primitives than the DUT: a ripple-carry
  // loop rather than `+`/`-`, iterated single-bit shifts rather than
  // `<<`/`>>`/`>>>`, per-bit loops rather than `&`/`|`/`^`, and 64-bit
  // sign-extended comparison rather than $signed().
  //
  // A reference model that reuses the operators under test is worthless: it
  // reproduces the DUT's mistakes and agrees with it enthusiastically. The
  // signedness trap that made SRA behave as SRL is exactly the kind of bug a
  // lazily written model would share.
  function automatic word_t ref_alu(input alu_op_e sel, input logic sa, input word_t a,
                                    input word_t b);
    word_t                 r;
    word_t                 addend;
    logic            [4:0] sh;
    logic                  carry;
    longint signed         as;
    longint signed         bs;
    longint unsigned       au;
    longint unsigned       bu;

    r  = '0;
    sh = b[4:0];  // RV32I: shift amounts are taken modulo 32

    // Explicit width extension instead of $signed()/$unsigned() casts, so the
    // model does not depend on the sign rules the DUT has to get right.
    as = {{32{a[31]}}, a};
    bs = {{32{b[31]}}, b};
    au = {32'b0, a};
    bu = {32'b0, b};

    case (sel)
      ALU_ADDSUB: begin
        // Subtraction as a + ~b + 1; sub_arith supplies both the inversion and
        // the incoming carry.
        addend = sa ? ~b : b;
        carry  = sa;
        for (int i = 0; i < 32; i++) begin
          r[i]  = a[i] ^ addend[i] ^ carry;
          carry = (a[i] & addend[i]) | (a[i] & carry) | (addend[i] & carry);
        end
      end

      ALU_SLL: begin
        r = a;
        for (int i = 0; i < int'(sh); i++) r = {r[30:0], 1'b0};
      end

      ALU_SRL_SRA: begin
        // One bit at a time, shifting in 0 for SRL and a copy of the current
        // MSB for SRA. Concatenation operands are self-determined, so no
        // signedness can leak in or out.
        r = a;
        for (int i = 0; i < int'(sh); i++) r = {sa ? r[31] : 1'b0, r[31:1]};
      end

      ALU_SLT:  r = (as < bs) ? 32'd1 : 32'd0;
      ALU_SLTU: r = (au < bu) ? 32'd1 : 32'd0;

      ALU_XOR: for (int i = 0; i < 32; i++) r[i] = a[i] ^ b[i];
      ALU_OR:  for (int i = 0; i < 32; i++) r[i] = a[i] | b[i];
      ALU_AND: for (int i = 0; i < 32; i++) r[i] = a[i] & b[i];

      default: r = 'x;
    endcase

    return r;
  endfunction

  // Operand pool: purely uniform randoms almost never land on the values that
  // break things, so weight the corners explicitly and mix in sparse and
  // small-magnitude patterns.
  function automatic word_t rand_operand();
    case ($urandom_range(
        0, 9
    ))
      0:       return 32'h0000_0000;
      1:       return NegOne;
      2:       return MinInt;
      3:       return MaxInt;
      4:       return 32'h0000_0001;
      5:       return {27'b0, 5'($urandom)};  // plausible shift amount
      6:       return 32'($urandom) & 32'($urandom);  // sparse ones
      7:       return 32'($urandom) | 32'($urandom);  // sparse zeros
      8:       return 32'h8000_0000 | 32'($urandom);  // sign bit always set
      default: return 32'($urandom);
    endcase
  endfunction

  // ---------------------------------------------------------------- tests --

  initial begin
    // ---- ADD --------------------------------------------------------------
    check(ALU_ADDSUB, 1'b0, 32'd5, 32'd3, 32'd8, "add 5+3");
    check(ALU_ADDSUB, 1'b0, 32'd0, 32'd0, 32'd0, "add 0+0");
    // RV32I addition wraps silently; there is no trap and no flag.
    check(ALU_ADDSUB, 1'b0, MaxInt, 32'd1, MinInt, "add MAX_INT+1 wraps");
    check(ALU_ADDSUB, 1'b0, NegOne, 32'd1, 32'd0, "add -1+1");
    check(ALU_ADDSUB, 1'b0, NegOne, NegOne, 32'hffff_fffe, "add -1 + -1");

    // ---- SUB --------------------------------------------------------------
    check(ALU_ADDSUB, 1'b1, 32'd8, 32'd3, 32'd5, "sub 8-3");
    check(ALU_ADDSUB, 1'b1, 32'd0, 32'd1, NegOne, "sub 0-1");
    check(ALU_ADDSUB, 1'b1, 32'd5, 32'd5, 32'd0, "sub 5-5");
    check(ALU_ADDSUB, 1'b1, MinInt, 32'd1, MaxInt, "sub MIN_INT-1 wraps");
    // The same operands under both settings of sub_arith must differ, or the
    // ADD/SUB select is stuck.
    check(ALU_ADDSUB, 1'b0, 32'd10, 32'd4, 32'd14, "addsub select: add 10+4");
    check(ALU_ADDSUB, 1'b1, 32'd10, 32'd4, 32'd6, "addsub select: sub 10-4");

    // ---- SLL --------------------------------------------------------------
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'd0, 32'h0000_0001, "sll 1<<0");
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'd1, 32'h0000_0002, "sll 1<<1");
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'd31, 32'h8000_0000, "sll 1<<31");
    check(ALU_SLL, 1'b0, 32'hffff_ffff, 32'd4, 32'hffff_fff0, "sll ffffffff<<4");
    check(ALU_SLL, 1'b0, 32'h1234_5678, 32'd8, 32'h3456_7800, "sll 12345678<<8");
    // Only src_b[4:0] is a shift amount. Using the full 32-bit operand gives
    // zero here instead of the ISA-mandated shift by (amount mod 32).
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'd32, 32'h0000_0001, "sll shamt=32 -> shift by 0");
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'd33, 32'h0000_0002, "sll shamt=33 -> shift by 1");
    check(ALU_SLL, 1'b0, 32'h0000_0001, 32'hffff_ffff, 32'h8000_0000,
          "sll shamt=-1 -> shift by 31");
    // There is no arithmetic left shift in RV32I; sub_arith must be ignored.
    check(ALU_SLL, 1'b1, 32'h0000_0001, 32'd1, 32'h0000_0002, "sll ignores sub_arith");

    // ---- SRL (sub_arith = 0) ----------------------------------------------
    check(ALU_SRL_SRA, 1'b0, 32'h0000_0010, 32'd4, 32'h0000_0001, "srl 10>>4");
    check(ALU_SRL_SRA, 1'b0, MinInt, 32'd4, 32'h0800_0000, "srl 80000000>>4 zero-fills");
    check(ALU_SRL_SRA, 1'b0, NegOne, 32'd31, 32'h0000_0001, "srl ffffffff>>31");
    check(ALU_SRL_SRA, 1'b0, MinInt, 32'd0, MinInt, "srl >>0 is identity");
    check(ALU_SRL_SRA, 1'b0, MinInt, 32'd33, 32'h4000_0000, "srl shamt=33 -> shift by 1");

    // ---- SRA (sub_arith = 1) ----------------------------------------------
    // The sign-fill cases. These are the ones that fail when the $signed()
    // cast is lost -- e.g. by sitting in a ternary whose other arm is
    // unsigned, which makes the whole expression unsigned and turns >>> back
    // into a logical shift.
    check(ALU_SRL_SRA, 1'b1, MinInt, 32'd4, 32'hf800_0000, "sra 80000000>>>4 sign-fills");
    check(ALU_SRL_SRA, 1'b1, MinInt, 32'd31, NegOne, "sra 80000000>>>31 -> all ones");
    check(ALU_SRL_SRA, 1'b1, NegOne, 32'd1, NegOne, "sra -1>>>1 stays -1");
    check(ALU_SRL_SRA, 1'b1, 32'hf000_0000, 32'd4, 32'hff00_0000, "sra f0000000>>>4");
    check(ALU_SRL_SRA, 1'b1, 32'hffff_fff0, 32'd4, NegOne, "sra -16>>>4 == -1");
    // Positive operands: SRA and SRL agree, so these pass either way. They are
    // here to prove the arithmetic path isn't broken in the other direction.
    check(ALU_SRL_SRA, 1'b1, MaxInt, 32'd4, 32'h07ff_ffff, "sra 7fffffff>>>4 zero-fills");
    check(ALU_SRL_SRA, 1'b1, 32'h0000_0010, 32'd4, 32'h0000_0001, "sra 10>>>4 (positive)");
    check(ALU_SRL_SRA, 1'b1, MinInt, 32'd0, MinInt, "sra >>>0 is identity");
    check(ALU_SRL_SRA, 1'b1, MinInt, 32'd33, 32'hc000_0000, "sra shamt=33 -> shift by 1");
    // Same operands, both settings of sub_arith: these must differ.
    check(ALU_SRL_SRA, 1'b0, MinInt, 32'd8, 32'h0080_0000, "srl/sra select: logical");
    check(ALU_SRL_SRA, 1'b1, MinInt, 32'd8, 32'hff80_0000, "srl/sra select: arithmetic");

    // ---- SLT (signed) -----------------------------------------------------
    check(ALU_SLT, 1'b0, 32'd1, 32'd2, 32'd1, "slt 1<2");
    check(ALU_SLT, 1'b0, 32'd2, 32'd1, 32'd0, "slt 2<1 false");
    check(ALU_SLT, 1'b0, 32'd5, 32'd5, 32'd0, "slt equal is false");
    check(ALU_SLT, 1'b0, NegOne, 32'd0, 32'd1, "slt -1<0");
    check(ALU_SLT, 1'b0, 32'd0, NegOne, 32'd0, "slt 0<-1 false");
    check(ALU_SLT, 1'b0, 32'hffff_fffe, NegOne, 32'd1, "slt -2<-1");
    // The overflow corner: computing src_a - src_b and testing bit 31 gives
    // 0x00000001, whose sign bit is 0, so a naive implementation answers
    // "false" for MIN_INT < MAX_INT.
    check(ALU_SLT, 1'b0, MinInt, MaxInt, 32'd1, "slt MIN_INT<MAX_INT (overflow corner)");
    check(ALU_SLT, 1'b0, MaxInt, MinInt, 32'd0, "slt MAX_INT<MIN_INT false");
    check(ALU_SLT, 1'b0, MinInt, 32'd0, 32'd1, "slt MIN_INT<0");
    check(ALU_SLT, 1'b0, 32'd0, MaxInt, 32'd1, "slt 0<MAX_INT");
    // Result is the full word 1 or 0, not just a bit dropped somewhere.
    check(ALU_SLT, 1'b0, NegOne, 32'd1, 32'h0000_0001, "slt result is 32-bit 1");
    check(ALU_SLT, 1'b1, 32'd1, 32'd2, 32'd1, "slt ignores sub_arith");

    // ---- SLTU (unsigned) --------------------------------------------------
    check(ALU_SLTU, 1'b0, 32'd1, 32'd2, 32'd1, "sltu 1<2");
    check(ALU_SLTU, 1'b0, 32'd2, 32'd1, 32'd0, "sltu 2<1 false");
    check(ALU_SLTU, 1'b0, 32'd5, 32'd5, 32'd0, "sltu equal is false");
    // Top bit set means "large", not "negative". A signed comparator here
    // answers the opposite of the ISA on all four of these.
    check(ALU_SLTU, 1'b0, NegOne, 32'd0, 32'd0, "sltu ffffffff<0 false");
    check(ALU_SLTU, 1'b0, 32'd0, NegOne, 32'd1, "sltu 0<ffffffff");
    check(ALU_SLTU, 1'b0, MinInt, MaxInt, 32'd0, "sltu 80000000<7fffffff false");
    check(ALU_SLTU, 1'b0, MaxInt, MinInt, 32'd1, "sltu 7fffffff<80000000");
    check(ALU_SLTU, 1'b1, 32'd1, 32'd2, 32'd1, "sltu ignores sub_arith");

    // ---- SLT vs SLTU must disagree ----------------------------------------
    // Same operands, different answers. If one is wired to the other's logic
    // these two checks cannot both pass.
    check(ALU_SLT, 1'b0, NegOne, 32'd1, 32'd1, "slt  -1 < 1 is true (signed)");
    check(ALU_SLTU, 1'b0, NegOne, 32'd1, 32'd0, "sltu -1 < 1 is false (unsigned)");

    // ---- bitwise ----------------------------------------------------------
    check(ALU_XOR, 1'b0, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'hff00_ff00, "xor");
    check(ALU_XOR, 1'b0, 32'hffff_ffff, 32'hffff_ffff, 32'h0000_0000, "xor self is zero");
    check(ALU_XOR, 1'b0, 32'h1234_5678, 32'h0000_0000, 32'h1234_5678, "xor with 0 is identity");
    check(ALU_OR, 1'b0, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'hfff0_fff0, "or");
    check(ALU_OR, 1'b0, 32'h1234_5678, 32'h0000_0000, 32'h1234_5678, "or with 0 is identity");
    check(ALU_AND, 1'b0, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'h00f0_00f0, "and");
    check(ALU_AND, 1'b0, 32'h1234_5678, 32'hffff_ffff, 32'h1234_5678, "and with -1 is identity");
    check(ALU_AND, 1'b0, 32'h1234_5678, 32'h0000_0000, 32'h0000_0000, "and with 0 is zero");
    // None of the bitwise ops has a variant, so sub_arith must not reach them.
    check(ALU_XOR, 1'b1, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'hff00_ff00, "xor ignores sub_arith");
    check(ALU_OR, 1'b1, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'hfff0_fff0, "or  ignores sub_arith");
    check(ALU_AND, 1'b1, 32'hf0f0_f0f0, 32'h0ff0_0ff0, 32'h00f0_00f0, "and ignores sub_arith");

    // ---- select decode ----------------------------------------------------
    // One operand pair through all eight selects. Every result must be
    // distinct from the ADD result, or that select is falling through.
    check(ALU_ADDSUB, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_00f4, "decode: ADDSUB");
    check(ALU_SLL, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_0f00, "decode: SLL");
    check(ALU_SLT, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_0000, "decode: SLT");
    check(ALU_SLTU, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_0000, "decode: SLTU");
    check(ALU_XOR, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_00f4, "decode: XOR");
    check(ALU_SRL_SRA, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_000f, "decode: SRL");
    check(ALU_OR, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_00f4, "decode: OR");
    check(ALU_AND, 1'b0, 32'h0000_00f0, 32'h0000_0004, 32'h0000_0000, "decode: AND");

    // ---- randomized cross-check against the reference model ---------------
    // Directed tests encode what the author thought to check. This layer
    // catches what nobody thought of -- in particular per-bit faults, which no
    // hand-written vector set can claim to cover.
    begin
      int unsigned errs_before;
      alu_op_e     sel;
      logic        sa;
      word_t       a;
      word_t       b;

      errs_before = errors;
      void'($urandom(RandomSeed));

      for (int unsigned t = 0; t < RandomVectors; t++) begin
        sel = alu_op_e'(3'($urandom_range(0, 7)));
        sa  = 1'($urandom_range(0, 1));
        a   = rand_operand();
        b   = rand_operand();
        check(sel, sa, a, b, ref_alu(sel, sa, a, b), $sformatf("random #%0d", t));
      end

      $display("tb_alu_execute: %0d random vectors vs reference model, %0d mismatches", RandomVectors,
               errors - errs_before);
    end

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_alu_execute: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_alu_execute: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_alu_execute: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_alu_execute);
    end
  end

endmodule
