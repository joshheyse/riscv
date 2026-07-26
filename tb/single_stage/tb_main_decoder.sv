// tb_main_decoder.sv — self-checking testbench for the main instruction decoder.
//
//   make sim TB=main_decoder      /      just sim main_decoder
//
// The main decoder is a pure function of the 7-bit opcode, which makes it one
// of the few modules in this design that can be tested *exhaustively*: there
// are only 128 possible inputs and every one is checked below, legal and
// illegal alike.
//
// Two distinct properties are verified:
//
//   1. For each opcode, the control outputs match the ISA.
//   2. The outputs depend on the opcode and NOTHING ELSE. Because the port is
//      the whole 32-bit instruction rather than just the opcode, nothing in
//      the language stops the decoder from reaching into funct3 or rs1. Each
//      opcode is therefore driven with several different values in the other
//      25 bits, and the outputs must not move.
//
// Property 2 is the one the port list would have given you for free if the
// module took `opcode` instead of `instr`. Since it doesn't, it gets tested.
//
// Signals the decode table marks x are checked only for being non-X, not
// pinned to a value -- for those opcodes nothing downstream selects them.
// Over-constraining a don't-care turns a testbench into an obstacle.

`timescale 1ns / 1ps

module tb_main_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 500_000;
  localparam int unsigned MaxPrintedFailures = 24;

  // How many different values of instr[31:7] to try per opcode when checking
  // that the decoder ignores them.
  localparam int unsigned NoiseVectors = 8;

  instr_u          instr;
  logic            reg_write;
  imm_src_t        imm_src;
  logic            mem_write;
  alu_src_t        alu_src;
  alu_result_src_t alu_result_src;
  result_src_t     result_src;
  logic            branch;
  logic            jump;
  logic            alu_op;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  int unsigned     printed = 0;

  main_decoder dut (
      .instr(instr),
      .reg_write(reg_write),
      .imm_src(imm_src),
      .mem_write(mem_write),
      .alu_src(alu_src),
      .alu_result_src(alu_result_src),
      .result_src(result_src),
      .branch(branch),
      .jump(jump),
      .alu_op(alu_op)
  );

  // ------------------------------------------------------------ expected --
  //
  // The RV32I decode table. Each function below is one column of it.
  //
  //   category op      branch jump alu_src imm_src alu_result_src result_src alu_op reg_write mem_write
  //   R-type   0110011 0      0    RS1_RS2 x       ALU            ALU        1      1         0
  //   I-ALU    0010011 0      0    RS1_IMM IMM_I   ALU            ALU        1      1         0
  //   load     0000011 0      0    RS1_IMM IMM_I   x              MEM        0      1         0
  //   store    0100011 0      0    RS1_IMM IMM_S   x              x          0      0         1
  //   branch   1100011 1      0    PC_IMM  IMM_B   x              x          0      0         0
  //   jal      1101111 0      1    PC_IMM  IMM_J   PC_PLUS4       ALU        0      1         0
  //   jalr     1100111 0      1    RS1_IMM IMM_I   PC_PLUS4       ALU        0      1         0
  //   lui      0110111 0      0    x       IMM_U   IMM            ALU        x      1         0
  //   auipc    0010111 0      0    PC_IMM  IMM_U   ALU            ALU        0      1         0

  // Every RV32I opcode that writes a destination register. Stores and branches
  // have no rd field at all, and an illegal opcode must be inert rather than
  // corrupting state -- so this is checked strictly for all 128 values.
  function automatic logic exp_reg_write(input logic [6:0] op);
    case (op)
      7'b0110011, 7'b0010011, 7'b0000011, 7'b1100111, 7'b1101111, 7'b0110111, 7'b0010111:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // Memory write enable. No don't-care: a spurious write corrupts state, so
  // illegal opcodes are checked as strictly as legal ones.
  function automatic logic exp_mem_write(input logic [6:0] op);
    return (op == 7'b0100011);  // store
  endfunction

  // Asserted for exactly one opcode each; a spurious branch or jump redirects
  // control flow, so both are checked strictly everywhere.
  function automatic logic exp_branch(input logic [6:0] op);
    return (op == 7'b1100011);
  endfunction

  function automatic logic exp_jump(input logic [6:0] op);
    case (op)
      7'b1101111, 7'b1100111: return 1'b1;  // jal, jalr
      default:                return 1'b0;
    endcase
  endfunction

  // Which immediate format `extend` must be told to use.
  //
  // The one that catches people: jalr is an I-type, NOT a J-type. Its
  // immediate is a plain 12-bit signed value at instr[31:20] -- the same
  // encoding as a load, which is why objdump prints `jalr ra,-4(sp)`. Only
  // jal uses the scrambled 21-bit J-type immediate.
  function automatic imm_src_t exp_imm_src(input logic [6:0] op);
    case (op)
      7'b0010011: return IMM_I;  // I-ALU:  addi/slti/xori/...
      7'b0000011: return IMM_I;  // load:   lw rd, imm(rs1)
      7'b1100111: return IMM_I;  // jalr:   I-type, not J-type
      7'b0100011: return IMM_S;  // store:  split across [31:25] and [11:7]
      7'b1100011: return IMM_B;  // branch: 13-bit, implicit zero LSB
      7'b1101111: return IMM_J;  // jal:    21-bit, implicit zero LSB
      7'b0110111: return IMM_U;  // lui
      7'b0010111: return IMM_U;  // auipc
      default:    return IMM_I;  // don't-care
    endcase
  endfunction

  // R-type, system and illegal opcodes carry no immediate at all.
  function automatic logic imm_src_matters(input logic [6:0] op);
    case (op)
      7'b0010011, 7'b0000011, 7'b1100111, 7'b0100011, 7'b1100011, 7'b1101111, 7'b0110111,
      7'b0010111:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // Which operand pair the ALU sees.
  //
  //   store  sw rs2, imm(rs1) -> RS1_IMM, because the ALU computes the
  //                              ADDRESS. The data being stored comes from rs2
  //                              but goes to memory's write port, not the ALU.
  //   branch                  -> PC_IMM, because the ALU computes the target;
  //                              a separate comparator decides taken/not-taken.
  function automatic alu_src_t exp_alu_src(input logic [6:0] op);
    case (op)
      7'b0110011: return SRC_RS1_RS2;  // R-type
      7'b0010011, 7'b0000011, 7'b0100011, 7'b1100111:
      return SRC_RS1_IMM;  // I-ALU, load, store, jalr
      7'b1100011, 7'b1101111, 7'b0010111: return SRC_PC_IMM;  // branch, jal, auipc
      default: return SRC_RS1_RS2;  // don't-care
    endcase
  endfunction

  // lui does not use the ALU at all -- the table marks its alu_src as x.
  function automatic logic alu_src_matters(input logic [6:0] op);
    case (op)
      7'b0110011, 7'b0010011, 7'b0000011, 7'b0100011, 7'b1100011, 7'b1101111, 7'b1100111,
      7'b0010111:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // First level of the writeback mux.
  //
  //   jal/jalr  -> PC_PLUS4. Note the ALU computed the jump TARGET, which goes
  //                to the PC; what lands in rd is the return address. Two
  //                different destinations from one instruction, which is
  //                exactly what this mux exists to arbitrate.
  //   lui       -> IMM, bypassing the ALU entirely.
  function automatic alu_result_src_t exp_alu_result_src(input logic [6:0] op);
    case (op)
      7'b1101111, 7'b1100111: return ALU_RES_PC_PLUS4;  // jal, jalr
      7'b0110111:             return ALU_RES_IMM;  // lui
      default:                return ALU_RES_ALU;
    endcase
  endfunction

  // Loads select memory downstream, and stores/branches write nothing, so this
  // mux's value is unobservable for all three.
  function automatic logic alu_result_src_matters(input logic [6:0] op);
    case (op)
      7'b0110011, 7'b0010011, 7'b1101111, 7'b1100111, 7'b0110111, 7'b0010111: return 1'b1;
      default:                                                                return 1'b0;
    endcase
  endfunction

  // Second level: the value chosen above, or memory. Only loads take memory.
  function automatic result_src_t exp_result_src(input logic [6:0] op);
    return (op == 7'b0000011) ? RESULT_MEM : RESULT_ALU;
  endfunction

  // Stores and branches don't write rd, so nothing observes this.
  function automatic logic result_src_matters(input logic [6:0] op);
    return exp_reg_write(op);
  endfunction

  // 0 = "just add" (addresses, jump targets), 1 = "decode the operation from
  // funct3/funct7". Only lui is a don't-care -- it never reaches the ALU.
  function automatic logic exp_alu_op(input logic [6:0] op);
    case (op)
      7'b0110011, 7'b0010011: return 1'b1;
      default:                return 1'b0;
    endcase
  endfunction

  function automatic logic alu_op_matters(input logic [6:0] op);
    case (op)
      7'b0110111: return 1'b0;  // lui
      default:    return 1'b1;
    endcase
  endfunction

  // -------------------------------------------------------------- naming --

  function automatic string opcode_name(input logic [6:0] op);
    case (op)
      7'b0110011: return "R-type";
      7'b0010011: return "I-type ALU";
      7'b0000011: return "load";
      7'b0100011: return "store";
      7'b1100011: return "branch";
      7'b1100111: return "jalr";
      7'b1101111: return "jal";
      7'b0110111: return "lui";
      7'b0010111: return "auipc";
      7'b1110011: return "system";
      default:    return "illegal";
    endcase
  endfunction

  function automatic string imm_name(input imm_src_t s);
    case (s)
      IMM_I:   return "IMM_I";
      IMM_S:   return "IMM_S";
      IMM_B:   return "IMM_B";
      IMM_J:   return "IMM_J";
      IMM_U:   return "IMM_U";
      default: return $sformatf("<%03b>", s);
    endcase
  endfunction

  function automatic string alu_src_name(input alu_src_t s);
    case (s)
      SRC_RS1_RS2: return "SRC_RS1_RS2";
      SRC_RS1_IMM: return "SRC_RS1_IMM";
      SRC_PC_IMM:  return "SRC_PC_IMM";
      default:     return $sformatf("<%02b>", s);
    endcase
  endfunction

  function automatic string alu_res_name(input alu_result_src_t s);
    case (s)
      ALU_RES_ALU:      return "ALU_RES_ALU";
      ALU_RES_PC_PLUS4: return "ALU_RES_PC_PLUS4";
      ALU_RES_IMM:      return "ALU_RES_IMM";
      default:          return $sformatf("<%02b>", s);
    endcase
  endfunction

  function automatic string result_name(input result_src_t s);
    return (s == RESULT_MEM) ? "RESULT_MEM" : "RESULT_ALU";
  endfunction

  // ------------------------------------------------------------- helpers --

  // $display, not $error: Verilator treats $error as $stop and would abort on
  // the first mismatch, hiding the rest of the sweep.
  task automatic fail(input string msg);
    errors++;
    if (printed < MaxPrintedFailures) begin
      printed++;
      $display("  FAIL %s", msg);
    end else if (printed == MaxPrintedFailures) begin
      printed++;
      $display("  ... further failures suppressed; summary counts are exact");
    end
  endtask

  task automatic chk_bit(input logic got, input logic exp, input logic matters, input string who,
                         input string name);
    checks++;
    if (matters) begin
      if (got !== exp) fail($sformatf("%s %0s: got %b, expected %b", who, name, got, exp));
    end else if (got === 1'bx) begin
      fail($sformatf("%s %0s is X on a don't-care opcode", who, name));
    end
  endtask

  // Enum-valued outputs. `got_s`/`exp_s` are the rendered names, so the
  // failure message says SRC_PC_IMM rather than 11.
  task automatic chk_enum(input logic [2:0] got, input logic [2:0] exp, input logic matters,
                          input string who, input string name, input string got_s,
                          input string exp_s);
    checks++;
    if (matters) begin
      if (got !== exp) fail($sformatf("%s %0s: got %0s, expected %0s", who, name, got_s, exp_s));
    end else if (^got === 1'bx) begin
      fail($sformatf("%s %0s is X on a don't-care opcode", who, name));
    end
  endtask

  // Drive one instruction and check every output against the table.
  task automatic check_all(input logic [6:0] op, input logic [24:0] upper, input string tag);
    string who;
    instr.raw = {upper, op};
    #1;
    who = $sformatf("%s %07b (%0s)", tag, op, opcode_name(op));

    chk_bit(reg_write, exp_reg_write(op), 1'b1, who, "reg_write");
    chk_bit(mem_write, exp_mem_write(op), 1'b1, who, "mem_write");
    chk_bit(branch, exp_branch(op), 1'b1, who, "branch");
    chk_bit(jump, exp_jump(op), 1'b1, who, "jump");
    chk_bit(alu_op, exp_alu_op(op), alu_op_matters(op), who, "alu_op");

    chk_enum(imm_src, exp_imm_src(op), imm_src_matters(op), who, "imm_src", imm_name(imm_src),
             imm_name(exp_imm_src(op)));
    chk_enum({1'b0, alu_src}, {1'b0, exp_alu_src(op)}, alu_src_matters(op), who, "alu_src",
             alu_src_name(alu_src), alu_src_name(exp_alu_src(op)));
    chk_enum({1'b0, alu_result_src}, {1'b0, exp_alu_result_src(op)}, alu_result_src_matters(op),
             who, "alu_result_src", alu_res_name(alu_result_src), alu_res_name(
             exp_alu_result_src(op)));
    chk_enum({2'b0, result_src}, {2'b0, exp_result_src(op)}, result_src_matters(op), who,
             "result_src", result_name(result_src), result_name(exp_result_src(op)));
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    logic [6:0] op;

    void'($urandom(32'h0dec0de5));

    // -- T1: exhaustive opcode sweep ---------------------------------------
    // All 128 values, upper bits held at zero.
    for (int unsigned o = 0; o < 128; o++) begin
      op = 7'(o);
      check_all(op, 25'b0, "T1 opcode");
    end

    // -- T2: the other 25 bits must not matter ------------------------------
    // A decoder that peeks at funct3, rs1 or funct7 shows up here and nowhere
    // in T1.
    for (int unsigned o = 0; o < 128; o++) begin
      op = 7'(o);
      for (int unsigned k = 0; k < NoiseVectors; k++) begin
        check_all(op, 25'($urandom), "T2 opcode");
      end

      // Both union views must agree about the opcode, which catches a struct
      // whose members drifted out of order.
      checks++;
      if (instr.r.opcode !== opcode_t'(op) || instr.i.opcode !== opcode_t'(op))
        fail($sformatf(
             "union views disagree: raw[6:0]=%07b r=%07b i=%07b", op, instr.r.opcode, instr.i.opcode
             ));
    end

    // -- T3: the specific opcodes, named ------------------------------------
    // Redundant with T1, but a failure here names the instruction rather than
    // a bit pattern, which is faster to act on.
    check_all(7'b0110011, 25'b0, "T3 R-type   add/sub/and/or/slt   ");
    check_all(7'b0010011, 25'b0, "T3 I-ALU    addi/slti/xori/slli  ");
    check_all(7'b0000011, 25'b0, "T3 load     lb/lh/lw/lbu/lhu     ");
    check_all(7'b0100011, 25'b0, "T3 store    sb/sh/sw             ");
    check_all(7'b1100011, 25'b0, "T3 branch   beq/bne/blt/bge/bltu ");
    check_all(7'b1100111, 25'b0, "T3 jalr                          ");
    check_all(7'b1101111, 25'b0, "T3 jal                           ");
    check_all(7'b0110111, 25'b0, "T3 lui                           ");
    check_all(7'b0010111, 25'b0, "T3 auipc                         ");
    check_all(7'b1110011, 25'b0, "T3 system   ecall/ebreak         ");

    // ------------------------------------------------------------ summary --
    if (errors == 0) begin
      $display("tb_main_decoder: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_main_decoder: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  // -------------------------------------------------------------- watchdog --
  initial begin
    #(TimeoutNs);
    $error("tb_main_decoder: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  // ------------------------------------------------------------- waveforms --
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_main_decoder);
    end
  end

endmodule
