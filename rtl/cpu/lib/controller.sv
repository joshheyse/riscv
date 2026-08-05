`timescale 1ns / 1ps

// Integrated control unit.
//
// This module is pure decode/glue:
//   * main_decoder chooses broad datapath controls from opcode
//   * alu_decoder refines the ALU operation from funct3/funct7
//   * branch_logic turns decoded flow + branch flags + funct3 into PC select
//
// The datapath owns the comparator and supplies `branch_flags`; the controller
// supplies `branch_sgnd` so the comparator can produce the correct `lt` flag.
//
module controller
  import riscv_pkg::*;
(
  input  instr_u        instr,
  input  branch_flags_t branch_flags,
  output control_t      ctrl
);

  logic            _alu_decode_en;
  logic            _main_op_illegal;
  logic            _alu_op_illegal;
  logic            _mem_op_illegal;
  logic            _system_op_illegal;
  logic            _instr_illegal;

  logic            _main_reg_write_en;
  logic            _csr_reg_write_en;
  execute_result_t _main_execute_result;
  csr_ctrl_t       _csr_ctrl;
  system_ctrl_t    _system_ctrl;

  assign _system_op_illegal = _system_ctrl.op == SYSTEM_OP_ILLEGAL;

  assign ctrl.csr = _csr_ctrl;
  assign ctrl.system = _system_ctrl;
  assign ctrl.execute_result = _csr_ctrl.en ? EXEC_RESULT_CSR : _main_execute_result;
  assign ctrl.branch_sgnd = ~instr.r.funct3.br.unsgnd;

  assign _csr_reg_write_en = _csr_ctrl.en && (instr.r.rd != 5'd0);
  assign ctrl.reg_write_en = _main_reg_write_en | _csr_reg_write_en;

  always_comb begin
    ctrl.trap = '0;
    _instr_illegal = _main_op_illegal | _alu_op_illegal | _mem_op_illegal | _system_op_illegal;

    if (_instr_illegal) begin
      ctrl.trap = '{valid: 1'b1, src: TRAP_SRC_ILLEGAL_INSTR, mtval: instr.raw};
    end else begin
      // slang lint_off case-enum-explicit
      case (_system_ctrl.op)
        SYSTEM_OP_ECALL: begin
          ctrl.trap.valid = 1'b1;
          ctrl.trap.src   = TRAP_SRC_ECALL;
          ctrl.trap.mtval = '0;
        end
        SYSTEM_OP_EBREAK: begin
          ctrl.trap.valid = 1'b1;
          ctrl.trap.src   = TRAP_SRC_EBREAK;
          ctrl.trap.mtval = '0;
        end
        default: begin
        end
      endcase
      // slang lint_on case-enum-explicit
    end
  end

  main_decoder _main_decoder (
    .instr(instr),
    .reg_write_en(_main_reg_write_en),
    .mem_write_en(ctrl.mem_write_en),
    .imm_format(ctrl.imm_format),
    .alu_operands(ctrl.alu_operands),
    .execute_result(_main_execute_result),
    .writeback_result(ctrl.writeback_result),
    .flow(ctrl.flow),
    .alu_decode_en(_alu_decode_en),
    .clear_pc_lsb(ctrl.clear_pc_lsb),
    .main_op_illegal(_main_op_illegal)
  );

  branch_logic _branch_logic (
    .flow  (ctrl.flow),
    .flags (branch_flags),
    .funct3(instr.r.funct3.br),
    .pc_src(ctrl.pc_src)
  );

  alu_decoder _alu_decoder (
    .alu_decode_en(_alu_decode_en),
    .instr(instr),
    .alu_op(ctrl.alu_op),
    .sub_arith(ctrl.sub_arith),
    .alu_op_illegal(_alu_op_illegal)
  );

  mem_decoder _mem_decoder (
    .instr(instr),
    .mem_size(ctrl.mem_size),
    .mem_unsigned(ctrl.mem_unsigned),
    .mem_op_illegal(_mem_op_illegal)
  );

  system_decoder _system_decoder (
    .instr(instr),
    .csr_ctrl(_csr_ctrl),
    .system_ctrl(_system_ctrl)
  );


endmodule
