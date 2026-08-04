// tb_integer_execute.sv - directed checks for the integer execute wrapper.
//
//   make sim TB=integer_execute
//   make wave TB=integer_execute

`timescale 1ns / 1ps

module tb_integer_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  control_t      _ctrl;
  br_funct3_t    _branch_funct3;
  pc_t           _pc;
  reg_data_t     _rs1_data;
  reg_data_t     _rs2_data;
  imm_t          _imm;
  alu_data_t     _alu_result;
  mem_data_t     _store_data;
  branch_flags_t _branch_flags;
  pc_src_t       _pc_src;

  int unsigned   _checks = 0;
  int unsigned   _errors = 0;

  integer_execute _dut (
    .ctrl(_ctrl),
    .branch_funct3(_branch_funct3),
    .pc(_pc),
    .rs1_data(_rs1_data),
    .rs2_data(_rs2_data),
    .imm(_imm),
    .alu_result(_alu_result),
    .store_data(_store_data),
    .branch_flags(_branch_flags),
    .pc_src(_pc_src)
  );

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, got, exp);
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got %b, expected %b", what, got, exp);
    end
  endtask

  task automatic expect_pc_src(input pc_src_t got, input pc_src_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got %s, expected %s", what, got.name(), exp.name());
    end
  endtask

  task automatic settle();
    #1;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_integer_execute);
    end

    _ctrl = '0;
    _ctrl.alu_op = ALU_ADDSUB;
    _ctrl.alu_operands = ALU_OPERANDS_RS1_RS2;
    _ctrl.flow = FLOW_NONE;
    _ctrl.branch_sgnd = 1'b1;
    _branch_funct3 = br_funct3_t'(3'b000);
    _pc = 32'h0000_1000;
    _rs1_data = 32'h0000_0007;
    _rs2_data = 32'h0000_0005;
    _imm = 32'h0000_0020;
    settle();
    expect_word(_alu_result, 32'h0000_000c, "rs1+rs2 ALU operands");
    expect_word(_store_data, 32'h0000_0005, "store data comes from rs2");
    expect_pc_src(_pc_src, PC_SRC_INC, "plain ALU op does not redirect");

    _ctrl.alu_operands = ALU_OPERANDS_RS1_IMM;
    settle();
    expect_word(_alu_result, 32'h0000_0027, "rs1+imm ALU operands");
    expect_word(_store_data, 32'h0000_0005, "store data ignores immediate operand");

    _ctrl.alu_operands = ALU_OPERANDS_PC_IMM;
    settle();
    expect_word(_alu_result, 32'h0000_1020, "pc+imm ALU operands");

    _ctrl.alu_operands = ALU_OPERANDS_RS1_RS2;
    _ctrl.flow = FLOW_BRANCH;
    _branch_funct3 = br_funct3_t'(3'b000);
    _rs1_data = 32'h0000_0042;
    _rs2_data = 32'h0000_0042;
    settle();
    expect_bit(_branch_flags.eq, 1'b1, "branch comparator eq");
    expect_bit(_branch_flags.lt, 1'b0, "branch comparator lt");
    expect_pc_src(_pc_src, PC_SRC_IEU_ADR, "taken beq redirects");

    _rs2_data = 32'h0000_0043;
    settle();
    expect_bit(_branch_flags.eq, 1'b0, "branch comparator not eq");
    expect_pc_src(_pc_src, PC_SRC_INC, "untaken beq does not redirect");

    _ctrl.flow = FLOW_JUMP;
    _branch_funct3 = br_funct3_t'(3'b010);
    settle();
    expect_pc_src(_pc_src, PC_SRC_IEU_ADR, "jump redirects regardless of branch funct3");

    _ctrl.flow = FLOW_BRANCH;
    _ctrl.branch_sgnd = 1'b1;
    _branch_funct3 = br_funct3_t'(3'b100);
    _rs1_data = 32'hffff_ffff;
    _rs2_data = 32'h0000_0001;
    settle();
    expect_bit(_branch_flags.lt, 1'b1, "signed branch compare sees -1 < 1");
    expect_pc_src(_pc_src, PC_SRC_IEU_ADR, "taken signed blt redirects");

    _ctrl.branch_sgnd = 1'b0;
    settle();
    expect_bit(_branch_flags.lt, 1'b0, "unsigned branch compare sees max > 1");
    expect_pc_src(_pc_src, PC_SRC_INC, "untaken unsigned bltu does not redirect");

    if (_errors == 0) begin
      $display("tb_integer_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_integer_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $display("tb_integer_execute: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
