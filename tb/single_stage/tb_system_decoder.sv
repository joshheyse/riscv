// tb_system_decoder.sv - directed checks for SYSTEM/CSR instruction decode.
//
//   make sim TB=system_decoder
//   make wave TB=system_decoder

`timescale 1ns / 1ps

module tb_system_decoder
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 100_000;
  localparam int unsigned MaxPrintedFailures = 20;

  instr_u       _instr;
  csr_ctrl_t    _csr_ctrl;
  system_ctrl_t _system_ctrl;

  int unsigned errors = 0;
  int unsigned checks = 0;
  int unsigned printed = 0;

  system_decoder _dut (
    .instr(_instr),
    .csr_ctrl(_csr_ctrl),
    .system_ctrl(_system_ctrl)
  );

  function automatic instr_t encode(input opcode_t opcode, input logic [11:0] imm,
                                    input sys_funct3_t funct3, input logic [4:0] rs1,
                                    input logic [4:0] rd);
    return {imm, rs1, funct3, rd, opcode};
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

  task automatic check(input opcode_t opcode, input logic [11:0] imm, input sys_funct3_t funct3,
                       input logic [4:0] rs1, input logic [4:0] rd, input logic exp_en,
                       input logic exp_write_en, input csr_op_t exp_op, input logic exp_use_zimm,
                       input system_ctrl_t exp_system_ctrl, input string what);
    _instr.raw = encode(opcode, imm, funct3, rs1, rd);
    #1;
    checks++;
    if (_csr_ctrl.en !== exp_en || _csr_ctrl.write_en !== exp_write_en ||
        _csr_ctrl.op !== exp_op || _csr_ctrl.use_zimm !== exp_use_zimm ||
        _system_ctrl.en !== exp_system_ctrl.en || _system_ctrl.mret !== exp_system_ctrl.mret ||
        _system_ctrl.ecall !== exp_system_ctrl.ecall ||
        _system_ctrl.ebreak !== exp_system_ctrl.ebreak ||
        _system_ctrl.wfi !== exp_system_ctrl.wfi ||
        _system_ctrl.illegal !== exp_system_ctrl.illegal) begin
      fail($sformatf(
           "%s opcode=%07b imm=%03h funct3=%03b rs1=%0d rd=%0d: got csr_en=%b write=%b op=%s zimm=%b system_en=%b mret=%b ecall=%b ebreak=%b wfi=%b illegal=%b, expected csr_en=%b write=%b op=%s zimm=%b system_en=%b mret=%b ecall=%b ebreak=%b wfi=%b illegal=%b",
           what,
           opcode,
           imm,
           funct3,
           rs1,
           rd,
           _csr_ctrl.en,
           _csr_ctrl.write_en,
           _csr_ctrl.op.name(),
           _csr_ctrl.use_zimm,
           _system_ctrl.en,
           _system_ctrl.mret,
           _system_ctrl.ecall,
           _system_ctrl.ebreak,
           _system_ctrl.wfi,
           _system_ctrl.illegal,
           exp_en,
           exp_write_en,
           exp_op.name(),
           exp_use_zimm,
           exp_system_ctrl.en,
           exp_system_ctrl.mret,
           exp_system_ctrl.ecall,
           exp_system_ctrl.ebreak,
           exp_system_ctrl.wfi,
           exp_system_ctrl.illegal
           ));
    end
  endtask

  initial begin
    check(OP_R, 12'h300, SYS_F3_RW, 5'd2, 5'd1, 1'b0, 1'b0, CSR_OP_RW, 1'b0, '0,
          "non-system ignored");

    check(OP_SYSTEM, 12'h300, SYS_F3_RW, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrw");
    check(OP_SYSTEM, 12'h300, SYS_F3_RS, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RS, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrs writes");
    check(OP_SYSTEM, 12'h300, SYS_F3_RC, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RC, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrc writes");
    check(OP_SYSTEM, 12'h300, SYS_F3_RWI, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RW, 1'b1,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrwi");
    check(OP_SYSTEM, 12'h300, SYS_F3_RSI, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RS, 1'b1,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrsi writes");
    check(OP_SYSTEM, 12'h300, SYS_F3_RCI, 5'd2, 5'd1, 1'b1, 1'b1, CSR_OP_RC, 1'b1,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrci writes");

    check(OP_SYSTEM, 12'h300, SYS_F3_RS, 5'd0, 5'd1, 1'b1, 1'b0, CSR_OP_RS, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrs rs1=x0 read");
    check(OP_SYSTEM, 12'h300, SYS_F3_RC, 5'd0, 5'd1, 1'b1, 1'b0, CSR_OP_RC, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrc rs1=x0 read");
    check(OP_SYSTEM, 12'h300, SYS_F3_RSI, 5'd0, 5'd1, 1'b1, 1'b0, CSR_OP_RS, 1'b1,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrsi zimm=0 read");
    check(OP_SYSTEM, 12'h300, SYS_F3_RCI, 5'd0, 5'd1, 1'b1, 1'b0, CSR_OP_RC, 1'b1,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "csrrci zimm=0 read");

    check(OP_SYSTEM, SYS_IMM_MRET, SYS_F3_PRIV, 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b1, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "mret");
    check(OP_SYSTEM, SYS_IMM_ECALL, SYS_F3_PRIV, 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b1, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b0},
          "ecall");
    check(OP_SYSTEM, SYS_IMM_EBREAK, SYS_F3_PRIV, 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b1, wfi: 1'b0, illegal: 1'b0},
          "ebreak");
    check(OP_SYSTEM, SYS_IMM_WFI, SYS_F3_PRIV, 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b1, illegal: 1'b0},
          "wfi");
    check(OP_SYSTEM, SYS_IMM_MRET, SYS_F3_PRIV, 5'd1, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b1},
          "privileged system op with nonzero rs1");
    check(OP_SYSTEM, SYS_IMM_MRET, SYS_F3_PRIV, 5'd0, 5'd1, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b1},
          "privileged system op with nonzero rd");
    check(OP_SYSTEM, 12'hfff, SYS_F3_PRIV, 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b1},
          "reserved privileged system immediate");
    check(OP_SYSTEM, 12'h300, sys_funct3_t'(3'b100), 5'd0, 5'd0, 1'b0, 1'b0, CSR_OP_RW, 1'b0,
          '{en: 1'b1, mret: 1'b0, ecall: 1'b0, ebreak: 1'b0, wfi: 1'b0, illegal: 1'b1},
          "reserved system funct3");

    if (errors == 0) begin
      $display("tb_system_decoder: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_system_decoder: FAIL (%0d/%0d checks failed)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $error("tb_system_decoder: timeout after %0d ns", TimeoutNs);
    $fatal(1);
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_system_decoder);
    end
  end

endmodule
