// tb_controller.sv — self-checking testbench for the integrated controller.
//
//   make sim TB=controller      /      just sim controller
//
// The controller is the glue around main_decoder, alu_decoder and branch_logic.
// This testbench checks that integration boundary directly: instruction fields
// go in, datapath flags go in, and the full control bundle comes out.

`timescale 1ns / 1ps

module tb_controller
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;
  localparam int unsigned MaxPrintedFailures = 24;

  instr_u          instr;
  branch_flags_t   branch_flags;
  logic            reg_write;
  logic            mem_write;
  imm_src_t        imm_src;
  alu_src_t        alu_src;
  alu_result_src_t alu_result_src;
  alu_select_t     alu_select;
  result_src_t     result_src;
  logic            sub_arith;
  pc_src_t         pc_src;
  logic            branch_sgnd;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  int unsigned     printed = 0;

  controller dut (
    .instr(instr),
    .branch_flags(branch_flags),
    .reg_write(reg_write),
    .mem_write(mem_write),
    .imm_src(imm_src),
    .alu_src(alu_src),
    .alu_result_src(alu_result_src),
    .alu_select(alu_select),
    .result_src(result_src),
    .sub_arith(sub_arith),
    .pc_src(pc_src),
    .branch_sgnd(branch_sgnd)
  );

  // ------------------------------------------------------------- helpers --

  function automatic instr_t encode(input logic [6:0] funct7, input logic [4:0] rs2,
                                    input logic [4:0] rs1, input funct3_t funct3,
                                    input logic [4:0] rd, input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic string op_name(input logic [6:0] op);
    case (op)
      OP_R:      return "R";
      OP_I_ALU:  return "I-ALU";
      OP_LOAD:   return "LOAD";
      OP_STORE:  return "STORE";
      OP_BRANCH: return "BRANCH";
      OP_JAL:    return "JAL";
      OP_JALR:   return "JALR";
      OP_LUI:    return "LUI";
      OP_AUIPC:  return "AUIPC";
      OP_SYSTEM: return "SYSTEM";
      default:   return "ILLEGAL";
    endcase
  endfunction

  function automatic logic exp_reg_write(input logic [6:0] op);
    case (op)
      OP_R, OP_I_ALU, OP_LOAD, OP_JALR, OP_JAL, OP_LUI, OP_AUIPC: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic exp_mem_write(input logic [6:0] op);
    return op == OP_STORE;
  endfunction

  function automatic logic exp_branch(input logic [6:0] op);
    return op == OP_BRANCH;
  endfunction

  function automatic logic exp_jump(input logic [6:0] op);
    return op == OP_JAL || op == OP_JALR;
  endfunction

  function automatic imm_src_t exp_imm_src(input logic [6:0] op);
    case (op)
      OP_I_ALU, OP_LOAD, OP_JALR: return IMM_I;
      OP_STORE:                   return IMM_S;
      OP_BRANCH:                  return IMM_B;
      OP_JAL:                     return IMM_J;
      OP_LUI, OP_AUIPC:           return IMM_U;
      default:                    return IMM_I;
    endcase
  endfunction

  function automatic alu_src_t exp_alu_src(input logic [6:0] op);
    case (op)
      OP_R:                                 return SRC_RS1_RS2;
      OP_I_ALU, OP_LOAD, OP_STORE, OP_JALR: return SRC_RS1_IMM;
      OP_BRANCH, OP_JAL, OP_AUIPC:          return SRC_PC_IMM;
      default:                              return SRC_RS1_RS2;
    endcase
  endfunction

  function automatic alu_result_src_t exp_alu_result_src(input logic [6:0] op);
    case (op)
      OP_JAL, OP_JALR: return ALU_RES_PC_PLUS4;
      OP_LUI:          return ALU_RES_IMM;
      default:         return ALU_RES_ALU;
    endcase
  endfunction

  function automatic result_src_t exp_result_src(input logic [6:0] op);
    return op == OP_LOAD ? RESULT_MEM : RESULT_ALU;
  endfunction

  function automatic logic exp_alu_op(input logic [6:0] op);
    return op == OP_R || op == OP_I_ALU;
  endfunction

  function automatic alu_select_t exp_alu_select(input logic [6:0] op, input funct3_t funct3);
    if (!exp_alu_op(op)) return ALU_ADDSUB;
    case (funct3)
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

  function automatic logic exp_sub_arith(input logic [6:0] op, input funct3_t funct3,
                                         input logic funct7_bit5);
    if (!exp_alu_op(op)) return 1'b0;
    case (funct3)
      3'b000:  return funct7_bit5 & op[5];
      3'b101:  return funct7_bit5;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic exp_branch_taken(input logic eq, input logic lt, input funct3_t funct3);
    case (funct3)
      3'b000:  return eq;
      3'b001:  return ~eq;
      3'b100:  return lt;
      3'b101:  return ~lt;
      3'b110:  return lt;
      3'b111:  return ~lt;
      default: return 1'b0;
    endcase
  endfunction

  function automatic pc_src_t exp_pc_src(input logic [6:0] op, input logic eq, input logic lt,
                                         input funct3_t funct3);
    return ((exp_branch(op) && exp_branch_taken(eq, lt, funct3)) || exp_jump(op)) ? PC_SRC_IEU_ADR :
        PC_SRC_INC;
  endfunction

  function automatic logic exp_branch_sgnd(input logic unsgnd);
    return ~unsgnd;
  endfunction

  task automatic check(input instr_t word, input logic eq, input logic lt, input string what);
    logic    [6:0] op;
    funct3_t       funct3;
    logic          funct7_bit5;

    op = word[6:0];
    funct3 = word[14:12];
    funct7_bit5 = word[30];

    instr.raw = word;
    branch_flags.eq = eq;
    branch_flags.lt = lt;
    #1;
    checks++;

    if (reg_write !== exp_reg_write(
            op
        ) || mem_write !== exp_mem_write(
            op
        ) || imm_src !== exp_imm_src(
            op
        ) || alu_src !== exp_alu_src(
            op
        ) || alu_result_src !== exp_alu_result_src(
            op
        ) || alu_select !== exp_alu_select(
            op, funct3
        ) || result_src !== exp_result_src(
            op
        ) || sub_arith !== exp_sub_arith(
            op, funct3, funct7_bit5
        ) || pc_src !== exp_pc_src(
            op, eq, lt, funct3
        ) || branch_sgnd !== exp_branch_sgnd(
            funct3[1]
        )) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL %-38s instr=0x%08h op=%s f3=%03b f7b5=%b eq=%b lt=%b", what, word,
                 op_name(op), funct3, funct7_bit5, eq, lt);
        $display(
            "       got reg=%b mem=%b imm=%s alu_src=%s alu_res=%s alu_sel=%s res=%s sub=%b pc=%s sgnd=%b",
            reg_write, mem_write, imm_src.name(), alu_src.name(), alu_result_src.name(),
            alu_select.name(), result_src.name(), sub_arith, pc_src.name(), branch_sgnd);
        $display(
            "       exp reg=%b mem=%b imm=%s alu_src=%s alu_res=%s alu_sel=%s res=%s sub=%b pc=%s sgnd=%b",
            exp_reg_write(op), exp_mem_write(op), exp_imm_src(op).name(), exp_alu_src(op).name(),
            exp_alu_result_src(op).name(), exp_alu_select(op, funct3).name(), exp_result_src(op
            ).name(), exp_sub_arith(op, funct3, funct7_bit5), exp_pc_src(op, eq, lt, funct3
            ).name(), exp_branch_sgnd(funct3[1]));
      end else if (printed == MaxPrintedFailures) begin
        printed++;
        $display("  ... further failures suppressed; see the summary for exact counts");
      end
    end
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_controller);
    end

    // Sweep all opcodes, all funct3 values, both funct7[5] values, and every
    // branch flag combination. Other instruction fields are irrelevant to the
    // controller and are held at recognizable constants.
    begin
      instr_t word;
      funct3_t funct3;
      logic [6:0] funct7;

      for (int unsigned op = 0; op < 128; op++) begin
        for (int unsigned f = 0; f < 8; f++) begin
          for (int unsigned f7b5 = 0; f7b5 < 2; f7b5++) begin
            for (int unsigned eq = 0; eq < 2; eq++) begin
              for (int unsigned lt = 0; lt < 2; lt++) begin
                funct3 = funct3_t'(f);
                funct7 = 7'b0000000;
                funct7[5] = 1'(f7b5);
                word = encode(funct7, 5'd3, 5'd2, funct3, 5'd1, 7'(op));
                check(word, 1'(eq), 1'(lt), $sformatf(
                      "sweep op=%07b f3=%03b f7b5=%0d eq=%0d lt=%0d", 7'(op), funct3, f7b5, eq, lt
                      ));
              end
            end
          end
        end
      end
      $display(
          "tb_controller: exhaustive sweep of %0d opcode/funct3/funct7/flag combinations complete",
          checks);
    end

    // Directed rows for the integration points most likely to be miswired.
    check(encode(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, OP_R), 1'b0, 1'b0, "R add selects ALU add");
    check(encode(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, OP_R), 1'b0, 1'b0,
          "R sub asserts sub_arith");
    check(encode(7'b1111111, 5'b11111, 5'd2, 3'b000, 5'd1, OP_I_ALU), 1'b0, 1'b0,
          "addi with bit 30 set remains add");
    check(encode(7'b0100000, 5'd4, 5'd2, 3'b101, 5'd1, OP_I_ALU), 1'b0, 1'b0,
          "srai asserts sub_arith");
    check(encode(7'b0000000, 5'd4, 5'd2, 3'b000, 5'd0, OP_BRANCH), 1'b1, 1'b0,
          "beq taken uses branch_flags.eq");
    check(encode(7'b0000000, 5'd4, 5'd2, 3'b110, 5'd0, OP_BRANCH), 1'b0, 1'b1,
          "bltu taken uses branch_flags.lt");
    check(encode(7'b0000000, 5'd0, 5'd2, 3'b000, 5'd1, OP_JALR), 1'b0, 1'b0,
          "jalr jumps regardless of flags");

    if (errors == 0) begin
      $display("tb_controller: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_controller: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $display("tb_controller: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
