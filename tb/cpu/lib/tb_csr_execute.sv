// tb_csr_execute.sv - directed checks for CSR execute combinational logic.
//
//   make sim TB=csr_execute
//   make wave TB=csr_execute

`timescale 1ns / 1ps

module tb_csr_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  csr_op_e     _csr_op;
  logic        _csr_use_zimm;
  csr_data_t   _csr_read_data;
  reg_data_t   _rs1_data;
  csr_zimm_t   _zimm;
  csr_data_t   _csr_result;
  csr_data_t   _csr_write_data;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  csr_execute _dut (
    .csr_op(_csr_op),
    .csr_use_zimm(_csr_use_zimm),
    .csr_read_data(_csr_read_data),
    .rs1_data(_rs1_data),
    .zimm(_zimm),
    .csr_result(_csr_result),
    .csr_write_data(_csr_write_data)
  );

  task automatic check(input csr_op_e op, input logic use_zimm, input csr_data_t read_data,
                       input reg_data_t rs1_data, input csr_zimm_t zimm,
                       input csr_data_t exp_result, input csr_data_t exp_write_data,
                       input string what);
    _csr_op = op;
    _csr_use_zimm = use_zimm;
    _csr_read_data = read_data;
    _rs1_data = rs1_data;
    _zimm = zimm;
    #1;

    _checks++;
    if (_csr_result !== exp_result) begin
      _errors++;
      $display("  FAIL %s result: got 0x%08h, expected 0x%08h", what, _csr_result, exp_result);
    end

    _checks++;
    if (_csr_write_data !== exp_write_data) begin
      _errors++;
      $display("  FAIL %s write_data: got 0x%08h, expected 0x%08h", what, _csr_write_data,
               exp_write_data);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_execute);
    end

    check(CSR_OP_RW, 1'b0, 32'h1234_abcd, 32'hfeed_cafe, 5'h1f, 32'h1234_abcd, 32'hfeed_cafe,
          "csrrw rs1");

    check(CSR_OP_RS, 1'b0, 32'h0000_00f0, 32'h0000_0f0f, 5'h00, 32'h0000_00f0, 32'h0000_0fff,
          "csrrs rs1");

    check(CSR_OP_RC, 1'b0, 32'hffff_00ff, 32'h0000_00f0, 5'h00, 32'hffff_00ff, 32'hffff_000f,
          "csrrc rs1");

    check(CSR_OP_RW, 1'b1, 32'hffff_ffff, 32'hdead_beef, 5'h1a, 32'hffff_ffff, 32'h0000_001a,
          "csrrwi zimm zero extends");

    check(CSR_OP_RS, 1'b1, 32'h0000_1000, 32'hffff_ffff, 5'h05, 32'h0000_1000, 32'h0000_1005,
          "csrrsi zimm");

    check(CSR_OP_RC, 1'b1, 32'h0000_101f, 32'hffff_ffff, 5'h0f, 32'h0000_101f, 32'h0000_1010,
          "csrrci zimm");

    check(csr_op_e'(2'b11), 1'b0, 32'h1234_5678, 32'h8765_4321, 5'h1f, 32'h0000_0000, 32'h0000_0000,
          "reserved csr op");

    if (_errors == 0) begin
      $display("tb_csr_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_csr_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $display("tb_csr_execute: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
