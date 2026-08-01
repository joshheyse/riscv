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
  input logic clk,
  input logic rst,

  output pc_t  pc,
  output logic halted,

  dbus_if.master dbus,
  ibus_if.master ibus
);

  typedef struct packed {
    instr_u instr;
    pc_t    pc;
    logic   valid;
  } instr_slot_t;

  typedef struct packed {
    logic            reg_write_en;
    logic            mem_write_en;
    imm_src_t        imm_src;
    alu_src_t        alu_src;
    alu_result_src_t alu_result_src;
    alu_select_t     alu_select;
    result_src_t     result_src;
    logic            sub_arith;
    pc_src_t         pc_src;
    logic            branch_sgnd;
    mem_size_t       mem_size;
    logic            mem_unsigned;
    logic            clear_pc_lsb;
    logic            illegal_instr;
  } control_t;

  instr_u        _instr;
  logic          _reg_write_en;
  branch_flags_t _branch_flags;
  pc_t           _raw_ieu_addr;
  pc_t           _ifu_ieu_addr;
  logic          _halt_now;
  logic          _pc_en;
  logic          _fetch_en;
  logic          _redirect_en;
  logic          _ifu_en;
  logic          _instr_valid;
  pc_src_t       _ifu_pc_src;

  control_t      _ctrl;
  instr_slot_t   _current;
  logic          _can_retire;
  pc_t           _pending_fetch_pc;
  logic          _fetch_pending;

  logic          _dbus_pending;
  logic          _dbus_instr;
  logic          _dbus_wait;
  logic          _load_complete;
  logic          _load_instr;
  word_t         _read_data;
  word_t         _write_data;

  assign _halt_now = halted || (_ctrl.illegal_instr && _instr_valid);
  assign _pc_en = !_halt_now && !_dbus_wait;
  assign _fetch_en = !_current.valid && !_fetch_pending && _pc_en;
  assign _redirect_en = _current.valid && _can_retire && (_ctrl.pc_src != PC_SRC_INC);
  assign _ifu_en = _fetch_en || _redirect_en;

  assign _ifu_ieu_addr = _ctrl.clear_pc_lsb ? {_raw_ieu_addr[31:1], 1'b0} : _raw_ieu_addr;
  assign _instr = _current.instr;
  assign _instr_valid = _current.valid;
  assign ibus.req.valid = _fetch_en;
  assign _can_retire = _current.valid && (!_dbus_instr || dbus.rsp.ready);

  assign _dbus_instr = _load_instr || _ctrl.mem_write_en;
  assign dbus.req.valid = _instr_valid && _dbus_instr && !_halt_now && !_dbus_pending;
  assign _dbus_wait = _instr_valid && _dbus_instr && !_halt_now && !dbus.rsp.ready;
  assign dbus.req.write_en = _ctrl.mem_write_en && _instr_valid && !_halt_now;
  assign _reg_write_en = _ctrl.reg_write_en && _instr_valid && !_halt_now && (!_load_instr || _load_complete);

  assign _ifu_pc_src = _redirect_en ? _ctrl.pc_src : PC_SRC_INC;

  assign _load_instr = _ctrl.result_src == RESULT_MEM;
  assign _load_complete = _instr_valid && _load_instr && dbus.rsp.ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (_ctrl.illegal_instr & _instr_valid) begin
      halted <= 1'b1;
    end
    if (rst || _halt_now) begin
      _dbus_pending <= 1'b0;
    end else if (dbus.req.valid && !dbus.rsp.ready) begin
      _dbus_pending <= 1'b1;
    end else if (_dbus_pending && dbus.rsp.ready) begin
      _dbus_pending <= 1'b0;
    end

    if (rst || _halt_now) begin
      _current <= '0;
    end else if (!_current.valid && ibus.rsp.ready) begin
      _current.valid <= 1'b1;
      _current.instr <= ibus.rsp.instr;
      _current.pc <= _pending_fetch_pc;
    end else if (_current.valid && _can_retire) begin
      _current.valid <= 1'b0;
    end

    if (rst) begin
      _fetch_pending <= 1'b0;
    end else if (ibus.rsp.ready) begin
      _fetch_pending <= 1'b0;
    end else if (_fetch_en) begin
      _fetch_pending <= 1'b1;
    end

    if (rst) begin
      _pending_fetch_pc <= '0;
    end else if (_fetch_en) begin
      _pending_fetch_pc <= ibus.req.addr;
    end

  end

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .pc_src(_ifu_pc_src),
    .pc_en(_ifu_en),
    .ieu_addr(_ifu_ieu_addr),
    .pc(pc),
    .imem_addr(ibus.req.addr)
  );

  lsu _lsu (
    .addr(dbus.req.addr),
    .write_data(_write_data),
    .mem_size(_ctrl.mem_size),
    .mem_unsigned(_ctrl.mem_unsigned),
    .read_data(_read_data),
    .mem_write_data(dbus.req.write_data),
    .mem_read_data(dbus.rsp.read_data),
    .write_mask(dbus.req.write_mask)
  );

  controller _controller (
    .instr(_instr),
    .branch_flags(_branch_flags),
    .reg_write_en(_ctrl.reg_write_en),
    .mem_write_en(_ctrl.mem_write_en),
    .imm_src(_ctrl.imm_src),
    .alu_src(_ctrl.alu_src),
    .alu_result_src(_ctrl.alu_result_src),
    .alu_select(_ctrl.alu_select),
    .result_src(_ctrl.result_src),
    .sub_arith(_ctrl.sub_arith),
    .pc_src(_ctrl.pc_src),
    .branch_sgnd(_ctrl.branch_sgnd),
    .mem_size(_ctrl.mem_size),
    .mem_unsigned(_ctrl.mem_unsigned),
    .clear_pc_lsb(_ctrl.clear_pc_lsb),
    .illegal_instr(_ctrl.illegal_instr)
  );

  datapath _datapath (
    .clk(clk),
    .instr(_instr),
    .pc(_current.pc),
    .reg_write_en(_reg_write_en),
    .imm_src(_ctrl.imm_src),
    .alu_src(_ctrl.alu_src),
    .alu_result_src(_ctrl.alu_result_src),
    .alu_select(_ctrl.alu_select),
    .result_src(_ctrl.result_src),
    .sub_arith(_ctrl.sub_arith),
    .branch_sgnd(_ctrl.branch_sgnd),
    .read_data(_read_data),
    .ieu_addr(_raw_ieu_addr),
    .alu_result(dbus.req.addr),
    .write_data(_write_data),
    .branch_flags(_branch_flags)
  );

endmodule
