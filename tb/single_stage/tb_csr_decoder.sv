// tb_csr_decoder.sv - directed checks for SYSTEM/CSR instruction decode.
//
//   make sim TB=csr_decoder
//   make wave TB=csr_decoder

`timescale 1ns / 1ps

module tb_csr_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;
  localparam int unsigned MaxPrintedFailures = 20;

  instr_u      _instr;
  logic        _csr_en;
  logic        _csr_write_en;
  csr_op_t     _csr_op;
  logic        _csr_use_zimm;
  logic        _csr_op_illegal;

  int unsigned errors = 0;
  int unsigned checks = 0;
  int unsigned printed = 0;

  csr_decoder _dut (
    .instr(_instr),
    .csr_en(_csr_en),
    .csr_write_en(_csr_write_en),
    .csr_op(_csr_op),
    .csr_use_zimm(_csr_use_zimm),
    .csr_op_illegal(_csr_op_illegal)
  );

  function automatic instr_t encode(input opcode_t opcode, input csr_funct3_t funct3,
                                    input logic [4:0] rs1);
    return {12'h300, rs1, funct3, 5'd1, opcode};
  endfunction

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

  task automatic check(input opcode_t opcode, input csr_funct3_t funct3, input logic [4:0] rs1,
                       input logic exp_en, input logic exp_write_en, input csr_op_t exp_op,
                       input logic exp_use_zimm, input logic exp_illegal, input string what);
    _instr.raw = encode(opcode, funct3, rs1);
    #1;
    checks++;
    if (_csr_en !== exp_en || _csr_write_en !== exp_write_en || _csr_op !== exp_op ||
        _csr_use_zimm !== exp_use_zimm || _csr_op_illegal !== exp_illegal) begin
      fail($sformatf(
           "%s opcode=%07b funct3=%03b rs1=%0d: got en=%b write=%b op=%s zimm=%b illegal=%b, expected en=%b write=%b op=%s zimm=%b illegal=%b",
           what,
           opcode,
           funct3,
           rs1,
           _csr_en,
           _csr_write_en,
           _csr_op.name(),
           _csr_use_zimm,
           _csr_op_illegal,
           exp_en,
           exp_write_en,
           exp_op.name(),
           exp_use_zimm,
           exp_illegal
           ));
    end
  endtask

  initial begin
    check(OP_R, CSR_F3_RW, 5'd2, 1'b0, 1'b0, CSR_OP_RW, 1'b0, 1'b0, "non-system ignored");

    check(OP_SYSTEM, CSR_F3_RW, 5'd2, 1'b1, 1'b1, CSR_OP_RW, 1'b0, 1'b0, "csrrw");
    check(OP_SYSTEM, CSR_F3_RS, 5'd2, 1'b1, 1'b1, CSR_OP_RS, 1'b0, 1'b0, "csrrs writes");
    check(OP_SYSTEM, CSR_F3_RC, 5'd2, 1'b1, 1'b1, CSR_OP_RC, 1'b0, 1'b0, "csrrc writes");
    check(OP_SYSTEM, CSR_F3_RWI, 5'd2, 1'b1, 1'b1, CSR_OP_RW, 1'b1, 1'b0, "csrrwi");
    check(OP_SYSTEM, CSR_F3_RSI, 5'd2, 1'b1, 1'b1, CSR_OP_RS, 1'b1, 1'b0, "csrrsi writes");
    check(OP_SYSTEM, CSR_F3_RCI, 5'd2, 1'b1, 1'b1, CSR_OP_RC, 1'b1, 1'b0, "csrrci writes");

    check(OP_SYSTEM, CSR_F3_RS, 5'd0, 1'b1, 1'b0, CSR_OP_RS, 1'b0, 1'b0, "csrrs rs1=x0 read");
    check(OP_SYSTEM, CSR_F3_RC, 5'd0, 1'b1, 1'b0, CSR_OP_RC, 1'b0, 1'b0, "csrrc rs1=x0 read");
    check(OP_SYSTEM, CSR_F3_RSI, 5'd0, 1'b1, 1'b0, CSR_OP_RS, 1'b1, 1'b0, "csrrsi zimm=0 read");
    check(OP_SYSTEM, CSR_F3_RCI, 5'd0, 1'b1, 1'b0, CSR_OP_RC, 1'b1, 1'b0, "csrrci zimm=0 read");

    check(OP_SYSTEM, CSR_F3_PRIV, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0, 1'b1,
          "privileged system op unsupported");
    check(OP_SYSTEM, csr_funct3_t'(3'b100), 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0, 1'b1,
          "reserved csr funct3");

    if (errors == 0) begin
      $display("tb_csr_decoder: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_csr_decoder: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $error("tb_csr_decoder: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_decoder);
    end
  end

endmodule
