// tb_alu_decoder.sv — self-checking testbench for the ALU decoder.
//
//   make sim TB=alu_decoder      /      just sim alu_decoder
//
// Purely combinational: drive inputs, settle, compare. No clock.
//
// The decoder is a function of exactly four things -- alu_op, funct3,
// funct7[5] and opcode[5] -- which is 2 x 8 x 2 x 2 = 64 combinations. The
// sweep covers all of them, and fills every *other* instruction bit with fresh
// random values on each pass, so a decoder that peeks at rs1, rs2, rd, the rest
// of funct7 or the rest of the opcode fails here even though its 64-entry truth
// table is correct.
//
// The case this testbench exists for is the sub_arith asymmetry:
//
//   funct3=000 (add/sub): sub_arith = funct7[5] & opcode[5]
//   funct3=101 (srl/sra): sub_arith = funct7[5]
//
// The gate on the first row is not cosmetic. For an I-type instruction, bit 30
// is part of the immediate, not a funct7 field -- `addi x1, x2, -1` has an
// immediate of 0xfff, so bit 30 is set, and an ungated decoder turns it into a
// subtract. The second row has no such hazard because a shift immediate is only
// 5 bits wide and the ISA fixes imm[11:5] to 0000000 or 0100000, which is
// exactly what makes SRAI decodable. Both directed sections below encode this.

`timescale 1ns / 1ps

module tb_alu_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;
  localparam int unsigned MaxPrintedFailures = 20;

  // How many times to repeat the 64-combination sweep with fresh random
  // don't-care bits. Fixed seed so a failure reproduces exactly.
  localparam int unsigned SweepPasses = 200;
  localparam int unsigned RandomSeed = 32'h00c0_ffee;

  // funct3 encodings for OP / OP-IMM.
  localparam funct3_t F3AddSub = 3'b000;
  localparam funct3_t F3Sll = 3'b001;
  localparam funct3_t F3Slt = 3'b010;
  localparam funct3_t F3Sltu = 3'b011;
  localparam funct3_t F3Xor = 3'b100;
  localparam funct3_t F3SrlSra = 3'b101;
  localparam funct3_t F3Or = 3'b110;
  localparam funct3_t F3And = 3'b111;

  // funct7 values that appear in RV32I.
  localparam logic [6:0] F7Zero = 7'b0000000;
  localparam logic [6:0] F7Alt = 7'b0100000;  // sub, sra, srai

  logic        alu_op;
  instr_u      instr;
  alu_select_t alu_select;
  logic        sub_arith;
  logic        illegal_alu;

  int unsigned errors = 0;
  int unsigned checks = 0;
  int unsigned printed = 0;

  alu_decoder dut (
      .alu_op(alu_op),
      .instr(instr),
      .alu_select(alu_select),
      .sub_arith(sub_arith),
      .illegal_alu(illegal_alu)
  );

  // ------------------------------------------------------------- helpers --

  function automatic instr_t encode(input logic [6:0] funct7, input logic [4:0] rs2,
                                    input logic [4:0] rs1, input funct3_t funct3,
                                    input logic [4:0] rd, input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  // $display rather than $error: Verilator treats $error as $stop and aborts on
  // the first mismatch, hiding every later failure. Count here, $fatal once at
  // the end so `make sim` still exits non-zero.
  task automatic check(input logic op, input instr_t word, input alu_select_t exp_sel,
                       input logic exp_sub, input logic exp_illegal, input string what);
    alu_op = op;
    instr.raw = word;
    #1;
    checks++;
    if (alu_select !== exp_sel || sub_arith !== exp_sub || illegal_alu !== exp_illegal) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display(
            "  FAIL %-36s alu_op=%b instr=0x%08h (f7=%07b f3=%03b op=%07b) -> %s/%b illegal=%b, expected %s/%b illegal=%b",
            what, op, word, word[31:25], word[14:12], word[6:0], alu_select.name(), sub_arith,
            illegal_alu, exp_sel.name(), exp_sub, exp_illegal);
      end else if (printed == MaxPrintedFailures) begin
        printed++;
        $display("  ... further failures suppressed; see the summary for exact counts");
      end
    end
  endtask

  // ------------------------------------------------------- reference model --

  // An explicit funct3 -> alu_select_t mapping, written from the ISA table.
  // The DUT gets this for free by casting, because alu_select_t was numbered to
  // mirror funct3 -- so the model must NOT cast, or it would agree with the DUT
  // by construction and prove nothing. Spelling the eight rows out is the whole
  // point: if anyone renumbers alu_select_t, these disagree and this testbench
  // is what tells you.
  function automatic alu_select_t ref_select(input logic op, input funct3_t f3);
    if (!op) return ALU_ADDSUB;  // address / target arithmetic
    case (f3)
      3'b000:  return ALU_ADDSUB;
      3'b001:  return ALU_SLL;
      3'b010:  return ALU_SLT;
      3'b011:  return ALU_SLTU;
      3'b100:  return ALU_XOR;
      3'b101:  return ALU_SRL_SRA;
      3'b110:  return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  function automatic logic ref_sub(input logic op, input logic [6:0] opcode, input funct3_t f3,
                                   input logic f7b5);
    if (!op) return 1'b0;
    if (opcode != OP_R && opcode != OP_I_ALU) return 1'b0;
    case (f3)
      3'b000:  return f7b5 & (opcode == OP_R);  // sub only exists as R-type; addi has no subi
      3'b101:  return f7b5;  // srai is a legal I-type, so no opcode gate
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic ref_illegal(input logic op, input logic [6:0] opcode, input funct3_t f3,
                                       input logic [6:0] f7);
    if (!op) return 1'b0;

    case (opcode)
      OP_R: begin
        case (f3)
          3'b000, 3'b101: return !(f7 == F7Zero || f7 == F7Alt);
          default:        return f7 != F7Zero;
        endcase
      end
      OP_I_ALU: begin
        case (f3)
          3'b001:  return f7 != F7Zero;
          3'b101:  return !(f7 == F7Zero || f7 == F7Alt);
          default: return 1'b0;
        endcase
      end
      default: return 1'b1;
    endcase
  endfunction

  // ---------------------------------------------------------------- tests --

  initial begin
    // ---- exhaustive sweep, with randomized don't-care bits ----------------
    begin
      instr_t word;
      funct3_t f3;
      logic [6:0] f7;
      logic [6:0] opc;

      void'($urandom(RandomSeed));

      for (int unsigned pass = 0; pass < SweepPasses; pass++) begin
        for (int unsigned op = 0; op < 2; op++) begin
          for (int unsigned f = 0; f < 8; f++) begin
            for (int unsigned f7b5 = 0; f7b5 < 2; f7b5++) begin
              for (int unsigned op5 = 0; op5 < 2; op5++) begin
                f3 = funct3_t'(f);
                // Every bit the decoder must ignore is randomized: funct7's
                // other six bits, rs1, rs2, rd, and the opcode's other six.
                f7 = 7'($urandom);
                f7[5] = 1'(f7b5);
                opc = 7'($urandom);
                opc[5] = 1'(op5);
                word = encode(f7, 5'($urandom), 5'($urandom), f3, 5'($urandom), opc);
                check(1'(op), word, ref_select(1'(op), f3), ref_sub(1'(op), opc, f3, 1'(f7b5)),
                      ref_illegal(1'(op), opc, f3, f7),
                      $sformatf("sweep op=%0d f3=%03b f7b5=%0d op5=%0d", op, f3, f7b5, op5));
              end
            end
          end
        end
      end
      $display("tb_alu_decoder: %0d passes over 64 combinations, randomized don't-care bits",
               SweepPasses);
    end

    // ---- R-type: add vs sub ------------------------------------------------
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3AddSub, 5'd1, OP_R), ALU_ADDSUB, 1'b0, 1'b0, "add");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3AddSub, 5'd1, OP_R), ALU_ADDSUB, 1'b1, 1'b0, "sub");

    // ---- I-type add: the bit-30 trap ---------------------------------------
    // addi x1, x2, -1 -> immediate 0xfff, so instruction bit 30 is SET. It is
    // immediate data, not a funct7 field. Decoding it as sub_arith turns
    // `addi x1, x2, -1` into `x2 - 0xfff`, which is the bug this row exists to
    // catch. There is no SUBI in RV32I.
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3AddSub, 5'd1, OP_I_ALU), ALU_ADDSUB, 1'b0, 1'b0,
          "addi with imm=-1 (bit 30 set) is still add");
    check(1'b1, encode(F7Alt, 5'd0, 5'd2, F3AddSub, 5'd1, OP_I_ALU), ALU_ADDSUB, 1'b0, 1'b0,
          "addi with imm=0x400 (bit 30 set) is still add");
    check(1'b1, encode(F7Zero, 5'd5, 5'd2, F3AddSub, 5'd1, OP_I_ALU), ALU_ADDSUB, 1'b0, 1'b0,
          "addi with small positive immediate");

    // ---- shifts: bit 30 IS functional, for both R and I type ---------------
    // A shift immediate is 5 bits, so imm[11:5] is free for the ISA to use --
    // which is why srai exists as an I-type at all. No opcode gate here.
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3SrlSra, 5'd1, OP_R), ALU_SRL_SRA, 1'b0, 1'b0, "srl");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3SrlSra, 5'd1, OP_R), ALU_SRL_SRA, 1'b1, 1'b0, "sra");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3SrlSra, 5'd1, OP_I_ALU), ALU_SRL_SRA, 1'b0, 1'b0, "srli");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3SrlSra, 5'd1, OP_I_ALU), ALU_SRL_SRA, 1'b1, 1'b0,
          "srai (I-type, bit 30 IS functional)");
    // slli's funct7 is fixed at zero, but prove the decoder doesn't leak
    // funct7[5] into a non-shift-right operation.
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Sll, 5'd1, OP_R), ALU_SLL, 1'b0, 1'b0, "sll");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Sll, 5'd1, OP_I_ALU), ALU_SLL, 1'b0, 1'b0, "slli");

    // ---- every other funct3 must ignore funct7[5] entirely -----------------
    // These are I-type instructions with negative immediates, so bit 30 is set.
    // Only funct3 000 and 101 may ever look at it.
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3Xor, 5'd1, OP_I_ALU), ALU_XOR, 1'b0, 1'b0,
          "xori with imm=-1 ignores bit 30");
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3Or, 5'd1, OP_I_ALU), ALU_OR, 1'b0, 1'b0,
          "ori with imm=-1 ignores bit 30");
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3And, 5'd1, OP_I_ALU), ALU_AND, 1'b0, 1'b0,
          "andi with imm=-1 ignores bit 30");
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3Slt, 5'd1, OP_I_ALU), ALU_SLT, 1'b0, 1'b0,
          "slti with imm=-1 ignores bit 30");
    check(1'b1, encode(7'b1111111, 5'b11111, 5'd2, F3Sltu, 5'd1, OP_I_ALU), ALU_SLTU, 1'b0, 1'b0,
          "sltiu with imm=-1 ignores bit 30");
    // ... and the R-type forms, where funct7[5] is genuinely 0 in the ISA but a
    // sloppy decoder might still route it.
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3Xor, 5'd1, OP_R), ALU_XOR, 1'b0, 1'b1,
          "xor ignores funct7[5]");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3Or, 5'd1, OP_R), ALU_OR, 1'b0, 1'b1,
          "or ignores funct7[5]");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3And, 5'd1, OP_R), ALU_AND, 1'b0, 1'b1,
          "and ignores funct7[5]");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3Slt, 5'd1, OP_R), ALU_SLT, 1'b0, 1'b1,
          "slt ignores funct7[5]");
    check(1'b1, encode(F7Alt, 5'd3, 5'd2, F3Sltu, 5'd1, OP_R), ALU_SLTU, 1'b0, 1'b1,
          "sltu ignores funct7[5]");

    // ---- the full OP / OP-IMM select decode --------------------------------
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Slt, 5'd1, OP_R), ALU_SLT, 1'b0, 1'b0, "slt");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Sltu, 5'd1, OP_R), ALU_SLTU, 1'b0, 1'b0,
          "sltu");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Xor, 5'd1, OP_R), ALU_XOR, 1'b0, 1'b0, "xor");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3Or, 5'd1, OP_R), ALU_OR, 1'b0, 1'b0, "or");
    check(1'b1, encode(F7Zero, 5'd3, 5'd2, F3And, 5'd1, OP_R), ALU_AND, 1'b0, 1'b0, "and");

    // ---- alu_op = 0 forces add, whatever funct3 says ------------------------
    // These are the instructions whose funct3 means something entirely
    // different -- a width for loads and stores, a branch condition for
    // BRANCH. A decoder that consults funct3 unconditionally computes SLT for
    // `lw` (funct3=010) and the load address is garbage.
    check(1'b0, encode(F7Zero, 5'd0, 5'd2, 3'b010, 5'd1, OP_LOAD), ALU_ADDSUB, 1'b0, 1'b0,
          "lw: funct3=010 must not decode as SLT");
    check(1'b0, encode(F7Zero, 5'd0, 5'd2, 3'b000, 5'd1, OP_LOAD), ALU_ADDSUB, 1'b0, 1'b0,
          "lb");
    check(1'b0, encode(F7Zero, 5'd0, 5'd2, 3'b101, 5'd1, OP_LOAD), ALU_ADDSUB, 1'b0, 1'b0,
          "lhu: funct3=101 must not decode as SRL");
    check(1'b0, encode(F7Zero, 5'd3, 5'd2, 3'b010, 5'd1, OP_STORE), ALU_ADDSUB, 1'b0, 1'b0,
          "sw");
    check(1'b0, encode(F7Zero, 5'd3, 5'd2, 3'b100, 5'd1, OP_BRANCH), ALU_ADDSUB, 1'b0, 1'b0,
          "blt: target is pc+imm, an add");
    check(1'b0, encode(F7Zero, 5'd3, 5'd2, 3'b111, 5'd1, OP_BRANCH), ALU_ADDSUB, 1'b0, 1'b0,
          "bgeu");
    check(1'b0, encode(F7Zero, 5'd0, 5'd0, 3'b000, 5'd1, OP_JAL), ALU_ADDSUB, 1'b0, 1'b0,
          "jal");
    check(1'b0, encode(F7Zero, 5'd0, 5'd2, 3'b000, 5'd1, OP_JALR), ALU_ADDSUB, 1'b0, 1'b0,
          "jalr");
    check(1'b0, encode(F7Zero, 5'd0, 5'd0, 3'b000, 5'd1, OP_AUIPC), ALU_ADDSUB, 1'b0, 1'b0,
          "auipc");
    // alu_op=0 must also suppress sub_arith even when bit 30 happens to be set
    // -- a store with a negative offset, for instance.
    check(1'b0, encode(7'b1111111, 5'b11111, 5'd2, 3'b010, 5'd1, OP_STORE), ALU_ADDSUB, 1'b0, 1'b0,
          "sw with negative offset: bit 30 set, still an add");
    check(1'b0, encode(7'b1111111, 5'b11111, 5'd2, 3'b010, 5'd1, OP_LOAD), ALU_ADDSUB, 1'b0, 1'b0,
          "lw with negative offset: bit 30 set, still an add");

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_alu_decoder: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_alu_decoder: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_alu_decoder: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_alu_decoder);
    end
  end

endmodule
