`timescale 1ns / 1ps

module tb_muldiv_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100;

  logic         _muldiv_decode_en;
  instr_u       _instr;
  muldiv_ctrl_t _muldiv_ctrl;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  muldiv_decoder _dut (
    .muldiv_decode_en(_muldiv_decode_en),
    .instr(_instr),
    .muldiv_ctrl(_muldiv_ctrl)
  );

  task automatic check_enabled(input logic [2:0] funct3, input muldiv_unit_t exp_unit,
                               input mul_op_t exp_mul_op, input div_op_t exp_div_op,
                               input string what);
    _muldiv_decode_en  = 1'b1;
    _instr             = '0;
    _instr.r.opcode    = OP_R;
    _instr.r.funct7    = 7'b0000001;
    _instr.r.funct3.raw = funct3;
    #1;

    _checks++;
    if (_muldiv_ctrl.en !== 1'b1 || _muldiv_ctrl.unit !== exp_unit ||
        _muldiv_ctrl.mul_op !== exp_mul_op || _muldiv_ctrl.div_op !== exp_div_op) begin
      _errors++;
      $error(
          "%s funct3=%03b: got en=%b unit=%s mul_op=%s div_op=%s, expected en=1 unit=%s mul_op=%s div_op=%s",
          what, funct3, _muldiv_ctrl.en, _muldiv_ctrl.unit.name(), _muldiv_ctrl.mul_op.name(),
          _muldiv_ctrl.div_op.name(), exp_unit.name(), exp_mul_op.name(), exp_div_op.name());
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_muldiv_decoder.vcd");
      $dumpvars(0, tb_muldiv_decoder);
    end

    check_enabled(3'b000, MULDIV_MUL, MUL_OP_LOW, DIV_OP_QUOTIENT_SIGNED, "mul");
    check_enabled(3'b001, MULDIV_MUL, MUL_OP_HIGH_SS, DIV_OP_QUOTIENT_UNSIGNED, "mulh");
    check_enabled(3'b010, MULDIV_MUL, MUL_OP_HIGH_SU, DIV_OP_REMAINDER_SIGNED, "mulhsu");
    check_enabled(3'b011, MULDIV_MUL, MUL_OP_HIGH_UU, DIV_OP_REMAINDER_UNSIGNED, "mulhu");
    check_enabled(3'b100, MULDIV_DIV, MUL_OP_LOW, DIV_OP_QUOTIENT_SIGNED, "div");
    check_enabled(3'b101, MULDIV_DIV, MUL_OP_HIGH_SS, DIV_OP_QUOTIENT_UNSIGNED, "divu");
    check_enabled(3'b110, MULDIV_DIV, MUL_OP_HIGH_SU, DIV_OP_REMAINDER_SIGNED, "rem");
    check_enabled(3'b111, MULDIV_DIV, MUL_OP_HIGH_UU, DIV_OP_REMAINDER_UNSIGNED, "remu");

    _muldiv_decode_en   = 1'b0;
    _instr.r.funct3.raw = 3'b111;
    #1;
    _checks++;
    if (_muldiv_ctrl.en !== 1'b0) begin
      _errors++;
      $error("disabled decoder asserted muldiv_ctrl.en");
    end

    if (_errors == 0) begin
      $display("tb_muldiv_decoder: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_muldiv_decoder: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_muldiv_decoder: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
