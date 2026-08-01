// tb_branch_logic.sv — self-checking testbench for the branch/jump PC select.
//
//   make sim TB=branch_logic      /      just sim branch_logic
//
// Purely combinational: drive inputs, settle, compare. No clock.
//
// The input space is 8 funct3 values x 4 flag combinations x branch x jump =
// 128 cases, so this sweeps it *exhaustively*. Nothing is sampled and nothing
// is left to chance; a passing run means the module is correct for every input
// it can ever see, which is a stronger statement than any random testbench can
// make. The directed section that follows the sweep is redundant as coverage --
// it exists to name the cases that matter, so a failure report points at a
// concept rather than at "case #77".
//
// What the vectors are looking for:
//
//   * the reserved 01x encodings never branching, which the mux-and-XOR form
//     only gets right via its kill term
//   * BEQ/BNE and BLT/BGE inverting with funct3[0] and nothing else
//   * branch=0 suppressing a taken branch, since funct3 and the flags are
//     whatever the current non-branch instruction happens to leave on the bus
//   * jump forcing the target regardless of branch, funct3 and the flags
//
// Note that eq=1 with lt=1 cannot occur in the real datapath -- the comparator
// never asserts both. The sweep drives it anyway: unreachable inputs still have
// to produce the table's answer per-flag, and constraining the sweep to
// "realistic" inputs would be assuming the comparator correct inside the
// testbench for a *different* module.

`timescale 1ns / 1ps

module tb_branch_logic
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;
  localparam int unsigned MaxPrintedFailures = 20;

  // RV32I BRANCH funct3 encodings.
  localparam funct3_t F3Beq = 3'b000;
  localparam funct3_t F3Bne = 3'b001;
  localparam funct3_t F3Rsvd2 = 3'b010;  // reserved -- never taken
  localparam funct3_t F3Rsvd3 = 3'b011;  // reserved -- never taken
  localparam funct3_t F3Blt = 3'b100;
  localparam funct3_t F3Bge = 3'b101;
  localparam funct3_t F3Bltu = 3'b110;
  localparam funct3_t F3Bgeu = 3'b111;

  logic          _branch;
  logic          _jump;
  branch_flags_t _flags;
  funct3_t       _funct3;
  pc_src_t       _pc_src;

  int unsigned   errors = 0;
  int unsigned   checks = 0;
  int unsigned   printed = 0;

  branch_logic _dut (
    .branch(_branch),
    .jump(_jump),
    .flags(_flags),
    .funct3(_funct3),
    .pc_src(_pc_src)
  );

  // ------------------------------------------------------------- helpers --

  // $display rather than $error: Verilator treats $error as $stop and aborts on
  // the first mismatch, hiding every later failure. Count here, $fatal once at
  // the end so `make sim` still exits non-zero.
  task automatic check(input logic br, input logic jmp, input logic f_eq, input logic f_lt,
                       input funct3_t f3, input pc_src_t exp, input string what);
    _branch  = br;
    _jump    = jmp;
    _flags.eq = f_eq;
    _flags.lt = f_lt;
    _funct3  = f3;
    #1;
    checks++;
    if (_pc_src !== exp) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL %-38s branch=%b jump=%b eq=%b lt=%b funct3=%03b -> %s, expected %s", what,
                 br, jmp, f_eq, f_lt, f3, _pc_src.name(), exp.name());
      end else if (printed == MaxPrintedFailures) begin
        printed++;
        $display("  ... further failures suppressed; see the summary for exact counts");
      end
    end
  endtask

  // ------------------------------------------------------- reference model --

  // A flat case over funct3, written from the ISA table rather than from the
  // DUT's structure. The DUT computes this as a 2:1 mux, an XOR with funct3[0]
  // and a kill term for the reserved encodings; a model that reused that
  // formulation would reproduce its mistakes -- in particular it would agree
  // enthusiastically about the 01x rows, which is exactly where the shortcut
  // form is easiest to get wrong.
  function automatic logic ref_taken(input logic f_eq, input logic f_lt, input funct3_t f3);
    case (f3)
      F3Beq:   return f_eq;
      F3Bne:   return ~f_eq;
      // The signed/unsigned distinction is not visible here: it was applied at
      // the comparator, so blt/bltu and bge/bgeu share a right-hand side.
      F3Blt:   return f_lt;
      F3Bge:   return ~f_lt;
      F3Bltu:  return f_lt;
      F3Bgeu:  return ~f_lt;
      default: return 1'b0;  // 010, 011 are not branches
    endcase
  endfunction

  function automatic pc_src_t ref_pc_src(input logic br, input logic jmp, input logic f_eq,
                                         input logic f_lt, input funct3_t f3);
    return ((br && ref_taken(f_eq, f_lt, f3)) || jmp) ? PC_SRC_IEU_ADR : PC_SRC_INC;
  endfunction

  // ---------------------------------------------------------------- tests --

  initial begin
    // ---- exhaustive sweep -------------------------------------------------
    begin
      funct3_t f3;
      for (int unsigned b = 0; b < 2; b++) begin
        for (int unsigned j = 0; j < 2; j++) begin
          for (int unsigned e = 0; e < 2; e++) begin
            for (int unsigned l = 0; l < 2; l++) begin
              for (int unsigned f = 0; f < 8; f++) begin
                f3 = funct3_t'(f);
                check(1'(b), 1'(j), 1'(e), 1'(l), f3, ref_pc_src(1'(b), 1'(j), 1'(e), 1'(l), f3),
                      $sformatf("sweep b=%0d j=%0d e=%0d l=%0d f3=%03b", b, j, e, l, f3));
              end
            end
          end
        end
      end
      $display("tb_branch_logic: exhaustive sweep of %0d input combinations complete", checks);
    end

    // ---- BEQ / BNE --------------------------------------------------------
    check(1'b1, 1'b0, 1'b1, 1'b0, F3Beq, PC_SRC_IEU_ADR, "beq taken when eq");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Beq, PC_SRC_INC, "beq not taken when !eq");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Bne, PC_SRC_IEU_ADR, "bne taken when !eq");
    check(1'b1, 1'b0, 1'b1, 1'b0, F3Bne, PC_SRC_INC, "bne not taken when eq");

    // ---- BLT / BGE --------------------------------------------------------
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Blt, PC_SRC_IEU_ADR, "blt taken when lt");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Blt, PC_SRC_INC, "blt not taken when !lt");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Bge, PC_SRC_IEU_ADR, "bge taken when !lt");
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Bge, PC_SRC_INC, "bge not taken when lt");

    // ---- BLTU / BGEU ------------------------------------------------------
    // Identical to BLT/BGE by construction: the comparator already applied the
    // signedness, so these must not consult funct3[1] for anything but the
    // reserved-encoding kill term.
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Bltu, PC_SRC_IEU_ADR, "bltu taken when lt");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Bltu, PC_SRC_INC, "bltu not taken when !lt");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Bgeu, PC_SRC_IEU_ADR, "bgeu taken when !lt");
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Bgeu, PC_SRC_INC, "bgeu not taken when lt");

    // ---- reserved encodings ----------------------------------------------
    // 010 and 011 are not branches. The mux-and-XOR form reaches these with
    // funct3[2]=0, so the flag mux hands it eq and it would otherwise behave
    // as beq/bne; only the kill term stops it. Every flag combination.
    check(1'b1, 1'b0, 1'b1, 1'b1, F3Rsvd2, PC_SRC_INC, "reserved 010 never taken (eq,lt)");
    check(1'b1, 1'b0, 1'b1, 1'b0, F3Rsvd2, PC_SRC_INC, "reserved 010 never taken (eq)");
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Rsvd2, PC_SRC_INC, "reserved 010 never taken (lt)");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Rsvd2, PC_SRC_INC, "reserved 010 never taken (none)");
    check(1'b1, 1'b0, 1'b1, 1'b1, F3Rsvd3, PC_SRC_INC, "reserved 011 never taken (eq,lt)");
    check(1'b1, 1'b0, 1'b1, 1'b0, F3Rsvd3, PC_SRC_INC, "reserved 011 never taken (eq)");
    check(1'b1, 1'b0, 1'b0, 1'b1, F3Rsvd3, PC_SRC_INC, "reserved 011 never taken (lt)");
    check(1'b1, 1'b0, 1'b0, 1'b0, F3Rsvd3, PC_SRC_INC, "reserved 011 never taken (none)");

    // ---- branch=0 suppresses everything -----------------------------------
    // On a non-branch instruction funct3 and the flags carry whatever that
    // instruction left on the bus. None of it may reach pc_src.
    check(1'b0, 1'b0, 1'b1, 1'b0, F3Beq, PC_SRC_INC, "branch=0 suppresses beq");
    check(1'b0, 1'b0, 1'b0, 1'b1, F3Blt, PC_SRC_INC, "branch=0 suppresses blt");
    check(1'b0, 1'b0, 1'b0, 1'b0, F3Bne, PC_SRC_INC, "branch=0 suppresses bne");
    check(1'b0, 1'b0, 1'b1, 1'b1, F3Bgeu, PC_SRC_INC, "branch=0 suppresses bgeu");

    // ---- jump overrides everything ----------------------------------------
    // jal/jalr are unconditional: the target is taken whatever branch, funct3
    // and the flags say. jalr's funct3 is 000, which is also beq's, so a
    // jump that leaned on the branch path would look correct only by luck.
    check(1'b0, 1'b1, 1'b0, 1'b0, F3Beq, PC_SRC_IEU_ADR, "jump taken (jalr funct3=000)");
    check(1'b0, 1'b1, 1'b0, 1'b0, F3Rsvd2, PC_SRC_IEU_ADR, "jump taken on reserved funct3");
    check(1'b0, 1'b1, 1'b1, 1'b1, F3Bge, PC_SRC_IEU_ADR, "jump taken, flags set");
    check(1'b1, 1'b1, 1'b0, 1'b0, F3Beq, PC_SRC_IEU_ADR, "jump wins over untaken branch");
    check(1'b1, 1'b1, 1'b1, 1'b0, F3Beq, PC_SRC_IEU_ADR, "jump with taken branch");

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_branch_logic: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_branch_logic: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_branch_logic: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_branch_logic);
    end
  end

endmodule
