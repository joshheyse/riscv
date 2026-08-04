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

  instr_u        _instr;
  branch_flags_t _branch_flags;
  control_t      _ctrl;

  int unsigned   errors = 0;
  int unsigned   checks = 0;
  int unsigned   printed = 0;

  controller _dut (
    .instr(_instr),
    .branch_flags(_branch_flags),
    .ctrl(_ctrl)
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
      OP_FENCE:  return "FENCE";
      default:   return "ILLEGAL";
    endcase
  endfunction

  function automatic logic exp_reg_write_en(input logic [6:0] op);
    case (op)
      OP_R, OP_I_ALU, OP_LOAD, OP_JALR, OP_JAL, OP_LUI, OP_AUIPC: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic exp_csr_en(input logic [6:0] op, input funct3_t funct3);
    if (op != OP_SYSTEM) return 1'b0;
    case (funct3)
      SYS_F3_RW, SYS_F3_RS, SYS_F3_RC, SYS_F3_RWI, SYS_F3_RSI, SYS_F3_RCI: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic exp_csr_reg_write_en(input logic [6:0] op, input funct3_t funct3,
                                                input logic [4:0] rd);
    return exp_csr_en(op, funct3) && (rd != 5'd0);
  endfunction

  function automatic logic exp_mem_write_en(input logic [6:0] op);
    return op == OP_STORE;
  endfunction

  function automatic logic exp_csr_write_en(input logic [6:0] op, input funct3_t funct3,
                                            input logic [4:0] rs1);
    if (!exp_csr_en(op, funct3)) return 1'b0;
    case (funct3)
      SYS_F3_RW, SYS_F3_RWI: return 1'b1;
      SYS_F3_RS, SYS_F3_RC, SYS_F3_RSI, SYS_F3_RCI: return rs1 != 5'd0;
      default: return 1'b0;
    endcase
  endfunction

  function automatic csr_op_t exp_csr_op(input logic [6:0] op, input funct3_t funct3);
    if (op != OP_SYSTEM) return CSR_OP_RW;
    case (funct3)
      SYS_F3_RS, SYS_F3_RSI: return CSR_OP_RS;
      SYS_F3_RC, SYS_F3_RCI: return CSR_OP_RC;
      default: return CSR_OP_RW;
    endcase
  endfunction

  function automatic logic exp_csr_use_zimm(input logic [6:0] op, input funct3_t funct3);
    return op == OP_SYSTEM && (funct3 == SYS_F3_RWI || funct3 == SYS_F3_RSI || funct3 == SYS_F3_RCI);
  endfunction

  function automatic logic exp_branch(input logic [6:0] op);
    return op == OP_BRANCH;
  endfunction

  function automatic logic exp_jump(input logic [6:0] op);
    return op == OP_JAL || op == OP_JALR;
  endfunction

  function automatic flow_t exp_flow(input logic [6:0] op);
    if (exp_branch(op)) return FLOW_BRANCH;
    if (exp_jump(op)) return FLOW_JUMP;
    return FLOW_NONE;
  endfunction

  function automatic imm_format_t exp_imm_format(input logic [6:0] op);
    case (op)
      OP_I_ALU, OP_LOAD, OP_JALR: return IMM_I;
      OP_STORE:                   return IMM_S;
      OP_BRANCH:                  return IMM_B;
      OP_JAL:                     return IMM_J;
      OP_LUI, OP_AUIPC:           return IMM_U;
      default:                    return IMM_I;
    endcase
  endfunction

  function automatic alu_operands_t exp_alu_operands(input logic [6:0] op);
    case (op)
      OP_R:                                 return ALU_OPERANDS_RS1_RS2;
      OP_I_ALU, OP_LOAD, OP_STORE, OP_JALR: return ALU_OPERANDS_RS1_IMM;
      OP_BRANCH, OP_JAL, OP_AUIPC:          return ALU_OPERANDS_PC_IMM;
      default:                              return ALU_OPERANDS_RS1_RS2;
    endcase
  endfunction

  function automatic execute_result_t exp_execute_result(input logic [6:0] op, input funct3_t funct3);
    if (exp_csr_en(op, funct3)) return EXEC_RESULT_CSR;
    case (op)
      OP_JAL, OP_JALR: return EXEC_RESULT_PC_PLUS4;
      OP_LUI:          return EXEC_RESULT_IMM;
      default:         return EXEC_RESULT_ALU;
    endcase
  endfunction

  function automatic writeback_result_t exp_writeback_result(input logic [6:0] op);
    return op == OP_LOAD ? WB_RESULT_MEM : WB_RESULT_EXEC;
  endfunction

  function automatic logic exp_alu_decode_en(input logic [6:0] op);
    return op == OP_R || op == OP_I_ALU;
  endfunction

  function automatic alu_op_t exp_alu_op(input logic [6:0] op, input funct3_t funct3);
    if (!exp_alu_decode_en(op)) return ALU_ADDSUB;
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
    if (!exp_alu_decode_en(op)) return 1'b0;
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

  function automatic mem_size_t exp_mem_size(input logic [6:0] op, input funct3_t funct3);
    case (op)
      OP_LOAD: begin
        case (funct3)
          3'b000, 3'b100: return MEM_SIZE_BYTE;
          3'b001, 3'b101: return MEM_SIZE_HALF;
          default:        return MEM_SIZE_WORD;
        endcase
      end

      OP_STORE: begin
        case (funct3)
          3'b000:  return MEM_SIZE_BYTE;
          3'b001:  return MEM_SIZE_HALF;
          default: return MEM_SIZE_WORD;
        endcase
      end

      default: begin
        return MEM_SIZE_WORD;
      end
    endcase
  endfunction

  function automatic logic exp_mem_unsigned(input logic [6:0] op, input funct3_t funct3);
    return op == OP_LOAD && (funct3 == 3'b100 || funct3 == 3'b101);
  endfunction

  function automatic logic mem_unsigned_matters(input logic [6:0] op);
    return op == OP_LOAD;
  endfunction

  function automatic logic exp_clear_pc_lsb(input logic [6:0] op);
    return op == OP_JALR;
  endfunction

  function automatic logic exp_main_illegal(input logic [6:0] op);
    case (op)
      OP_R, OP_I_ALU, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC, OP_FENCE,
      OP_SYSTEM:
      return 1'b0;
      default: return 1'b1;
    endcase
  endfunction

  function automatic logic exp_alu_illegal(input logic [6:0] op, input funct3_t funct3,
                                           input logic [6:0] funct7);
    case (op)
      OP_R: begin
        case (funct3)
          3'b000, 3'b101: return !(funct7 == 7'b0000000 || funct7 == 7'b0100000);
          default:        return funct7 != 7'b0000000;
        endcase
      end
      OP_I_ALU: begin
        case (funct3)
          3'b001:  return funct7 != 7'b0000000;
          3'b101:  return !(funct7 == 7'b0000000 || funct7 == 7'b0100000);
          default: return 1'b0;
        endcase
      end
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic exp_mem_illegal(input logic [6:0] op, input funct3_t funct3);
    case (op)
      OP_LOAD: begin
        case (funct3)
          3'b000, 3'b001, 3'b010, 3'b100, 3'b101: return 1'b0;
          default:                                return 1'b1;
        endcase
      end

      OP_STORE: begin
        case (funct3)
          3'b000, 3'b001, 3'b010: return 1'b0;
          default:                return 1'b1;
        endcase
      end

      default: begin
        return 1'b0;
      end
    endcase
  endfunction

  function automatic logic exp_csr_illegal(input logic [6:0] op, input funct3_t funct3);
    if (op != OP_SYSTEM) return 1'b0;

    case (funct3)
      SYS_F3_RW, SYS_F3_RS, SYS_F3_RC, SYS_F3_RWI, SYS_F3_RSI, SYS_F3_RCI: return 1'b0;
      default: return 1'b1;
    endcase
  endfunction

  function automatic logic exp_illegal_instr(input logic [6:0] op, input funct3_t funct3,
                                             input logic [6:0] funct7);
    return exp_main_illegal(op) || exp_alu_illegal(op, funct3, funct7) ||
        exp_mem_illegal(op, funct3) || exp_csr_illegal(op, funct3);
  endfunction

  task automatic check(input instr_t word, input logic eq, input logic lt, input string what);
    logic    [6:0] op;
    funct3_t       funct3;
    logic    [6:0] funct7;
    logic          funct7_bit5;
    logic    [4:0] rd;
    logic    [4:0] rs1;
    logic          mem_unsigned_bad;

    op = word[6:0];
    funct3 = word[14:12];
    funct7 = word[31:25];
    funct7_bit5 = word[30];
    rd = word[11:7];
    rs1 = word[19:15];

    _instr.raw = word;
    _branch_flags.eq = eq;
    _branch_flags.lt = lt;
    #1;
    checks++;
    mem_unsigned_bad = mem_unsigned_matters(op) &&
        (_ctrl.mem_unsigned !== exp_mem_unsigned(op, funct3));

    if (_ctrl.reg_write_en !== (exp_reg_write_en(
            op
        ) | exp_csr_reg_write_en(
            op, funct3, rd
        )) || _ctrl.mem_write_en !== exp_mem_write_en(
            op
        ) || _ctrl.csr_en !== exp_csr_en(
            op, funct3
        ) || _ctrl.csr_write_en !== exp_csr_write_en(
            op, funct3, rs1
        ) || _ctrl.csr_op !== exp_csr_op(
            op, funct3
        ) || _ctrl.csr_use_zimm !== exp_csr_use_zimm(
            op, funct3
        ) || _ctrl.imm_format !== exp_imm_format(
            op
        ) || _ctrl.alu_operands !== exp_alu_operands(
            op
        ) || _ctrl.execute_result !== exp_execute_result(
            op, funct3
        ) || _ctrl.alu_op !== exp_alu_op(
            op, funct3
        ) || _ctrl.writeback_result !== exp_writeback_result(
            op
        ) || _ctrl.flow !== exp_flow(
            op
        ) || _ctrl.sub_arith !== exp_sub_arith(
            op, funct3, funct7_bit5
        ) || _ctrl.pc_src !== exp_pc_src(
            op, eq, lt, funct3
        ) || _ctrl.branch_sgnd !== exp_branch_sgnd(
            funct3[1]
        ) || _ctrl.mem_size !== exp_mem_size(
            op, funct3
        ) || mem_unsigned_bad || _ctrl.clear_pc_lsb !== exp_clear_pc_lsb(
            op
        ) || _ctrl.illegal_instr !== exp_illegal_instr(
            op, funct3, funct7
        )) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL %-38s instr=0x%08h op=%s f3=%03b f7b5=%b eq=%b lt=%b", what, word,
                 op_name(op), funct3, funct7_bit5, eq, lt);
        $display(
            "       got reg=%b mem=%b csr_en=%b csr_write=%b csr_op=%s csr_zimm=%b imm=%s alu_operands=%s alu_res=%s alu_sel=%s res=%s flow=%s sub=%b pc=%s sgnd=%b mem_size=%s mem_unsigned=%b clear_pc_lsb=%b illegal=%b",
            _ctrl.reg_write_en, _ctrl.mem_write_en, _ctrl.csr_en, _ctrl.csr_write_en,
            _ctrl.csr_op.name(), _ctrl.csr_use_zimm, _ctrl.imm_format.name(),
            _ctrl.alu_operands.name(), _ctrl.execute_result.name(), _ctrl.alu_op.name(),
            _ctrl.writeback_result.name(), _ctrl.flow.name(), _ctrl.sub_arith, _ctrl.pc_src.name(),
            _ctrl.branch_sgnd, _ctrl.mem_size.name(), _ctrl.mem_unsigned, _ctrl.clear_pc_lsb,
            _ctrl.illegal_instr);
        $display(
            "       exp reg=%b mem=%b csr_en=%b csr_write=%b csr_op=%s csr_zimm=%b imm=%s alu_operands=%s alu_res=%s alu_sel=%s res=%s flow=%s sub=%b pc=%s sgnd=%b mem_size=%s mem_unsigned=%b clear_pc_lsb=%b illegal=%b",
            exp_reg_write_en(op) | exp_csr_reg_write_en(op, funct3, rd), exp_mem_write_en(op),
            exp_csr_en(op, funct3), exp_csr_write_en(op, funct3, rs1), exp_csr_op(op, funct3
            ).name(), exp_csr_use_zimm(op, funct3), exp_imm_format(op).name(), exp_alu_operands(op
            ).name(), exp_execute_result(op, funct3).name(), exp_alu_op(op, funct3).name(),
            exp_writeback_result(op).name(), exp_flow(op).name(), exp_sub_arith(
            op, funct3, funct7_bit5), exp_pc_src(op, eq, lt, funct3).name(), exp_branch_sgnd(
            funct3[1]), exp_mem_size(op, funct3).name(), exp_mem_unsigned(op, funct3),
            exp_clear_pc_lsb(op), exp_illegal_instr(op, funct3, funct7));
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
      instr_t        word;
      funct3_t       funct3;
      logic    [6:0] funct7;

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
