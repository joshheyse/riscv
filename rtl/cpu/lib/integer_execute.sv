`timescale 1ns / 1ps

module integer_execute
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,
  input logic valid,
  input logic cancel,
  input logic result_ready,

  /* verilator lint_off UNUSEDSIGNAL */
  input control_t   ctrl,
  /* verilator lint_on UNUSEDSIGNAL */
  input br_funct3_t branch_funct3,
  input pc_t        pc,
  input reg_data_t  rs1_data,
  input reg_data_t  rs2_data,
  input imm_t       imm,

  output integer_data_t alu_result,
  output mem_data_t     store_data,
  output pc_src_t       pc_src,
  output logic          execute_wait
);

  integer_data_t _src_a;
  integer_data_t _src_b;
  branch_flags_t _branch_flags;
  integer_data_t _alu_result;
  logic          _mul_selected;
  mul_req_t      _mul_req;
  mul_rsp_t      _mul_rsp;
  logic          _div_selected;
  div_req_t      _div_req;
  div_rsp_t      _div_rsp;

  /* verilator lint_off UNUSEDSIGNAL */
  logic          _mul_req_ready;
  logic          _div_req_ready;
  /* verilator lint_on UNUSEDSIGNAL */

  assign _src_a = ctrl.integer_operands_sel[1] ? pc : rs1_data;
  assign _src_b = ctrl.integer_operands_sel[0] ? imm : rs2_data;
  assign store_data = rs2_data;

  alu_execute _alu_execute (
    .src_a(_src_a),
    .src_b(_src_b),
    .ctrl(ctrl.alu),
    .alu_result(_alu_result)
  );

  mul_execute _mul_execute (
    .clk(clk),
    .rst(rst),
    .cancel(cancel),
    .req(_mul_req),
    .rsp_ready(result_ready),
    .req_ready(_mul_req_ready),
    .rsp(_mul_rsp)
  );

  div_execute _div_execute (
    .clk(clk),
    .rst(rst),
    .cancel(cancel),
    .req(_div_req),
    .rsp_ready(result_ready),
    .req_ready(_div_req_ready),
    .rsp(_div_rsp)
  );

  comparator _execute_comparator (
    .src_a(rs1_data),
    .src_b(rs2_data),
    .sngd(ctrl.branch_sgnd),
    .branch_flags(_branch_flags)
  );

  branch_logic _execute_branch_logic (
    .flow  (ctrl.flow),
    .flags (_branch_flags),
    .funct3(branch_funct3),
    .pc_src(pc_src)
  );

  always_comb begin
    _mul_selected = valid && ctrl.muldiv.en && (ctrl.muldiv.unit == MULDIV_MUL);
    _div_selected = valid && ctrl.muldiv.en && (ctrl.muldiv.unit == MULDIV_DIV);
    _mul_req = '{valid: _mul_selected, src_a: _src_a, src_b: _src_b, op: ctrl.muldiv.mul_op};
    _div_req = '{valid: _div_selected, src_a: _src_a, src_b: _src_b, op: ctrl.muldiv.div_op};
    execute_wait = (_mul_selected && !_mul_rsp.valid) || (_div_selected && !_div_rsp.valid);

    alu_result = '0;
    if (ctrl.muldiv.en) begin
      if (ctrl.muldiv.unit == MULDIV_DIV) begin
        alu_result = _div_rsp.result;
      end else if (ctrl.muldiv.unit == MULDIV_MUL) begin
        alu_result = _mul_rsp.result;
      end
    end else begin
      alu_result = _alu_result;
    end
  end

endmodule
