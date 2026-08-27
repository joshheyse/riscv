// tb_integer_execute.sv - directed checks for the integer execute wrapper.
//
//   make sim TB=integer_execute
//   make wave TB=integer_execute

`timescale 1ns / 1ps

module tb_integer_execute
  import riscv_pkg::*;
();

  localparam int unsigned ClockPeriodNs = 10;
  localparam int unsigned TimeoutCycles = 1_000;

  logic          _clk;
  logic          _rst;
  logic          _valid;
  logic          _cancel;
  logic          _result_ready;
  control_t      _ctrl;
  br_funct3_t    _branch_funct3;
  pc_t           _pc;
  reg_data_t     _rs1_data;
  reg_data_t     _rs2_data;
  imm_t          _imm;
  integer_data_t _alu_result;
  mem_data_t     _store_data;
  pc_src_t       _pc_src;
  logic          _execute_wait;

  int unsigned   _checks = 0;
  int unsigned   _errors = 0;

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriodNs / 2) _clk = ~_clk;
  end

  integer_execute _dut (
    .clk(_clk),
    .rst(_rst),
    .valid(_valid),
    .cancel(_cancel),
    .result_ready(_result_ready),
    .ctrl(_ctrl),
    .branch_funct3(_branch_funct3),
    .pc(_pc),
    .rs1_data(_rs1_data),
    .rs2_data(_rs2_data),
    .imm(_imm),
    .alu_result(_alu_result),
    .store_data(_store_data),
    .pc_src(_pc_src),
    .execute_wait(_execute_wait)
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

  task automatic check_div(input div_op_t op, input integer_data_t src_a,
                           input integer_data_t src_b, input integer_data_t expected,
                           input string what);
    @(negedge _clk);
    _ctrl.muldiv.unit = MULDIV_DIV;
    _ctrl.muldiv.div_op = op;
    _rs1_data = src_a;
    _rs2_data = src_b;
    _valid = 1'b1;
    #1;
    expect_bit(_execute_wait, 1'b1, {what, " starts multicycle wait"});

    while (_execute_wait) begin
      @(negedge _clk);
    end
    expect_word(_alu_result, expected, what);

    _result_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _result_ready = 1'b0;
    _valid = 1'b0;
  endtask

  task automatic check_mul(input mul_op_t op, input integer_data_t src_a,
                           input integer_data_t src_b, input integer_data_t expected,
                           input string what);
    @(negedge _clk);
    _ctrl.muldiv.unit = MULDIV_MUL;
    _ctrl.muldiv.mul_op = op;
    _rs1_data = src_a;
    _rs2_data = src_b;
    _valid = 1'b1;
    #1;
    expect_bit(_execute_wait, 1'b1, {what, " starts multicycle wait"});

    while (_execute_wait) begin
      @(negedge _clk);
    end
    expect_word(_alu_result, expected, what);

    _result_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _result_ready = 1'b0;
    _valid = 1'b0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_integer_execute);
    end

    _rst = 1'b1;
    _valid = 1'b0;
    _cancel = 1'b0;
    _result_ready = 1'b0;
    _ctrl = '0;
    _ctrl.alu.op = ALU_ADDSUB;
    _ctrl.integer_operands_sel = INTEGER_OPERANDS_RS1_RS2;
    _ctrl.flow = FLOW_NONE;
    _ctrl.branch_sgnd = 1'b1;
    _branch_funct3 = br_funct3_t'(3'b000);
    _pc = 32'h0000_1000;
    _rs1_data = 32'h0000_0007;
    _rs2_data = 32'h0000_0005;
    _imm = 32'h0000_0020;
    repeat (3) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;
    settle();
    expect_word(_alu_result, 32'h0000_000c, "rs1+rs2 ALU operands");
    expect_word(_store_data, 32'h0000_0005, "store data comes from rs2");
    expect_pc_src(_pc_src, PC_SRC_INC, "plain ALU op does not redirect");

    _ctrl.integer_operands_sel = INTEGER_OPERANDS_RS1_IMM;
    settle();
    expect_word(_alu_result, 32'h0000_0027, "rs1+imm ALU operands");
    expect_word(_store_data, 32'h0000_0005, "store data ignores immediate operand");

    _ctrl.integer_operands_sel = INTEGER_OPERANDS_PC_IMM;
    settle();
    expect_word(_alu_result, 32'h0000_1020, "pc+imm ALU operands");

    _ctrl.integer_operands_sel = INTEGER_OPERANDS_RS1_RS2;
    _ctrl.flow = FLOW_BRANCH;
    _branch_funct3 = br_funct3_t'(3'b000);
    _rs1_data = 32'h0000_0042;
    _rs2_data = 32'h0000_0042;
    settle();
    expect_pc_src(_pc_src, PC_SRC_IEU_ADR, "taken beq redirects");

    _rs2_data = 32'h0000_0043;
    settle();
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
    expect_pc_src(_pc_src, PC_SRC_IEU_ADR, "taken signed blt redirects");

    _ctrl.branch_sgnd = 1'b0;
    settle();
    expect_pc_src(_pc_src, PC_SRC_INC, "untaken unsigned bltu does not redirect");

    _ctrl.flow = FLOW_NONE;
    _ctrl.integer_operands_sel = INTEGER_OPERANDS_RS1_RS2;
    _ctrl.muldiv.en = 1'b1;
    check_mul(MUL_OP_LOW, 32'hffff_ffff, 32'h0000_0002, 32'hffff_fffe,
              "MUL result overrides ALU result");

    check_div(DIV_OP_QUOTIENT_SIGNED, -32'd7, 32'd3, 32'hffff_fffe,
              "DIV result overrides ALU result");
    check_div(DIV_OP_REMAINDER_UNSIGNED, 32'hffff_ffff, 32'd2, 32'h0000_0001,
              "REM result selected from divider");

    _ctrl.muldiv.en = 1'b0;
    _ctrl.alu.op = ALU_XOR;
    _rs1_data = 32'hf0f0_0f0f;
    _rs2_data = 32'h0ff0_f00f;
    settle();
    expect_word(_alu_result, 32'hff00_ff00, "disabled M control restores ALU result");

    if (_errors == 0) begin
      $display("tb_integer_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_integer_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_integer_execute: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
