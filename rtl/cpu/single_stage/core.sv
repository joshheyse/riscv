`timescale 1ns / 1ps

// Single-cycle RV32I processor core.
//
// This module owns fetch sequencing, decode, execute, branch decision, and
// writeback. Instruction memory and data memory live outside the core so a
// board or SoC wrapper can replace RAM with memory-mapped peripherals.
//
//   IFU.pc -> instruction bus -> instr
//      instr        -> controller -> control bundle
//      instr        -> datapath   -> _branch_flags / data address / store data
//      _branch_flags -> controller -> _pc_src
//      data bus     -> datapath writeback
//
// The `pc` output is both the instruction-memory byte address and a useful
// debug/visibility signal for testbenches and early board bring-up.
//
module core
  import riscv_pkg::*;
(
  input  logic          clk,
  input  logic          rst,
  input  instr_u        instr,
  output pc_t           pc,
  output pc_t           imem_addr,
  output logic          halted,
  output logic          imem_en,
         dbus_if.master dbus
);

  logic            _reg_write_en;
  imm_src_t        _imm_src;
  alu_src_t        _alu_src;
  alu_result_src_t _alu_result_src;
  alu_select_t     _alu_select;
  result_src_t     _result_src;
  logic            _sub_arith;
  pc_src_t         _pc_src;
  logic            _branch_sgnd;
  branch_flags_t   _branch_flags;
  logic            _clear_pc_lsb;
  pc_t             _raw_ieu_addr;
  pc_t             _ifu_ieu_addr;
  logic            _halt_now;
  logic            _illegal_instr;
  logic            _pc_en;
  logic            _raw_reg_write_en;
  logic            _raw_mem_write_en;
  logic            _instr_valid;
  pc_src_t         _ifu_pc_src;

  logic            _dbus_pending;
  logic            _dbus_instr;
  logic            _dbus_wait;
  logic            _load_complete;
  logic            _load_instr;

  assign _ifu_ieu_addr = _clear_pc_lsb ? {_raw_ieu_addr[31:1], 1'b0} : _raw_ieu_addr;

  assign _halt_now = halted || (_illegal_instr && _instr_valid);
  assign _dbus_instr = _load_instr || _raw_mem_write_en;
  assign dbus.valid = _instr_valid && _dbus_instr && !_halt_now && !_dbus_pending;
  assign _dbus_wait = _instr_valid && _dbus_instr && !_halt_now && !dbus.ready;
  assign _pc_en = !_halt_now && !_dbus_wait;
  assign imem_en = _pc_en;
  assign _reg_write_en = _raw_reg_write_en && _instr_valid && !_halt_now && (!_load_instr || _load_complete);
  assign dbus.write_en = _raw_mem_write_en && _instr_valid && !_halt_now;

  assign _ifu_pc_src = _instr_valid ? _pc_src : PC_SRC_INC;

  assign _load_instr = _result_src == RESULT_MEM;
  assign _load_complete = _instr_valid && _load_instr && dbus.ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (_illegal_instr & _instr_valid) begin
      halted <= 1'b1;
    end
    if (rst || _halt_now) begin
      _dbus_pending <= 1'b0;
    end else if (dbus.valid && !dbus.ready) begin
      _dbus_pending <= 1'b1;
    end else if (_dbus_pending && dbus.ready) begin
      _dbus_pending <= 1'b0;
    end
  end

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .pc_src(_ifu_pc_src),
    .pc_en(_pc_en),
    .ieu_addr(_ifu_ieu_addr),
    .pc(pc),
    .imem_addr(imem_addr),
    .instr_valid(_instr_valid)
  );

  controller _controller (
    .instr(instr),
    .branch_flags(_branch_flags),
    .reg_write_en(_raw_reg_write_en),
    .mem_write_en(_raw_mem_write_en),
    .imm_src(_imm_src),
    .alu_src(_alu_src),
    .alu_result_src(_alu_result_src),
    .alu_select(_alu_select),
    .result_src(_result_src),
    .sub_arith(_sub_arith),
    .pc_src(_pc_src),
    .branch_sgnd(_branch_sgnd),
    .mem_size(dbus.size),
    .mem_unsigned(dbus.mem_unsigned),
    .clear_pc_lsb(_clear_pc_lsb),
    .illegal_instr(_illegal_instr)
  );

  datapath _datapath (
    .clk(clk),
    .instr(instr),
    .pc(pc),
    .reg_write_en(_reg_write_en),
    .imm_src(_imm_src),
    .alu_src(_alu_src),
    .alu_result_src(_alu_result_src),
    .alu_select(_alu_select),
    .result_src(_result_src),
    .sub_arith(_sub_arith),
    .branch_sgnd(_branch_sgnd),
    .read_data(dbus.read_data),
    .ieu_addr(_raw_ieu_addr),
    .alu_result(dbus.addr),
    .write_data(dbus.write_data),
    .branch_flags(_branch_flags)
  );

endmodule
