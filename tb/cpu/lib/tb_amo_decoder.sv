`timescale 1ns / 1ps

module tb_amo_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100;

  logic      _amo_decode_en;
  instr_u    _instr;
  amo_ctrl_t _amo_ctrl;
  logic      _amo_op_illegal;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  amo_decoder _dut (
    .amo_decode_en(_amo_decode_en),
    .instr(_instr),
    .amo_ctrl(_amo_ctrl),
    .amo_op_illegal(_amo_op_illegal)
  );

  task automatic check(input amo_op_e op, input regaddr_t rs2, input logic aq, input logic rl,
                       input logic exp_illegal, input string what);
    _amo_decode_en = 1'b1;
    _instr = '0;
    _instr.amo = '{
        op: op,
        aq: aq,
        rl: rl,
        rs2: rs2,
        rs1: 5'd3,
        funct3: AMO_F3_WORD,
        rd: 5'd4,
        opcode: OP_AMO
    };
    #1;

    _checks++;
    if (_amo_ctrl.en !== 1'b1 || _amo_ctrl.op !== op || _amo_ctrl.aq !== aq ||
        _amo_ctrl.rl !== rl || _amo_op_illegal !== exp_illegal) begin
      _errors++;
      $error("%s: got en=%b op=%s aq=%b rl=%b illegal=%b", what, _amo_ctrl.en,
             _amo_ctrl.op.name(), _amo_ctrl.aq, _amo_ctrl.rl, _amo_op_illegal);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_amo_decoder.vcd");
      $dumpvars(0, tb_amo_decoder);
    end

    check(AMO_OP_ADD, 5'd1, 1'b0, 1'b0, 1'b0, "amoadd.w");
    check(AMO_OP_SWAP, 5'd1, 1'b1, 1'b0, 1'b0, "amoswap.w.aq");
    check(AMO_OP_LR, 5'd0, 1'b0, 1'b1, 1'b0, "lr.w.rl");
    check(AMO_OP_SC, 5'd1, 1'b1, 1'b1, 1'b0, "sc.w.aqrl");
    check(AMO_OP_XOR, 5'd1, 1'b0, 1'b0, 1'b0, "amoxor.w");
    check(AMO_OP_OR, 5'd1, 1'b0, 1'b0, 1'b0, "amoor.w");
    check(AMO_OP_AND, 5'd1, 1'b0, 1'b0, 1'b0, "amoand.w");
    check(AMO_OP_MIN, 5'd1, 1'b0, 1'b0, 1'b0, "amomin.w");
    check(AMO_OP_MAX, 5'd1, 1'b0, 1'b0, 1'b0, "amomax.w");
    check(AMO_OP_MINU, 5'd1, 1'b0, 1'b0, 1'b0, "amominu.w");
    check(AMO_OP_MAXU, 5'd1, 1'b0, 1'b0, 1'b0, "amomaxu.w");
    check(AMO_OP_LR, 5'd1, 1'b0, 1'b0, 1'b1, "lr.w rejects nonzero rs2");

    _instr.amo.op = amo_op_e'(5'b00101);
    #1;
    _checks++;
    if (!_amo_op_illegal) begin
      _errors++;
      $error("reserved funct5 was accepted");
    end

    _instr.amo.op = AMO_OP_ADD;
    _instr.amo.funct3 = amo_funct3_e'(3'b011);
    #1;
    _checks++;
    if (!_amo_op_illegal) begin
      _errors++;
      $error("non-word funct3 was accepted");
    end

    _instr.amo.funct3 = AMO_F3_WORD;
    _instr.amo.opcode = OP_R;
    #1;
    _checks++;
    if (!_amo_op_illegal) begin
      _errors++;
      $error("non-AMO opcode was accepted");
    end

    _amo_decode_en = 1'b0;
    #1;
    _checks++;
    if (_amo_ctrl.en || _amo_op_illegal) begin
      _errors++;
      $error("disabled decoder asserted enable or illegal");
    end

    if (_errors == 0) begin
      $display("tb_amo_decoder: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_amo_decoder: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_amo_decoder: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
