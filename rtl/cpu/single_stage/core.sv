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

  typedef enum logic [1:0] {
    CORE_FETCH,
    CORE_EXEC,
    CORE_MEM,
    CORE_HALT
  } core_state_t;

  logic          _reg_write_en;
  branch_flags_t _branch_flags;
  pc_t           _raw_ieu_addr;
  pc_t           _ifu_ieu_addr;
  logic          _redirect_en;
  logic          _ifu_en;
  pc_src_t       _ifu_pc_src;

  control_t      _ctrl;
  instr_slot_t   _current;

  logic          _in_fetch;
  logic          _in_exec;
  logic          _in_mem;
  logic          _in_halt;
  logic          _is_load;
  logic          _is_store;
  logic          _is_mem_op;
  logic          _illegal;
  logic          _exec_done;
  logic          _mem_done;
  logic          _retire;
  mem_data_t     _read_data;
  mem_data_t     _write_data;

  core_state_t   _state;
  core_state_t   _state_next;

  assign _in_fetch = _state == CORE_FETCH;
  assign _in_exec = _state == CORE_EXEC;
  assign _in_mem = _state == CORE_MEM;
  assign _in_halt = _state == CORE_HALT;

  assign _is_load = _ctrl.writeback_result == WB_RESULT_MEM;
  assign _is_store = _ctrl.mem_write_en;
  assign _is_mem_op = _is_load || _is_store;
  assign _illegal = _in_exec && _ctrl.illegal_instr;
  assign _exec_done = _in_exec && !_illegal && !_is_mem_op;
  assign _mem_done = ((_in_exec || _in_mem) && _is_mem_op && dbus.rsp.ready);
  assign _retire = _exec_done || _mem_done;
  assign _redirect_en = _retire && (_ctrl.pc_src != PC_SRC_INC);
  assign _ifu_en = _retire;
  assign _ifu_ieu_addr = _ctrl.clear_pc_lsb ? {_raw_ieu_addr[31:1], 1'b0} : _raw_ieu_addr;
  assign _ifu_pc_src = _redirect_en ? _ctrl.pc_src : PC_SRC_INC;

  assign ibus.req.valid = _in_fetch;
  assign dbus.req.valid = _is_mem_op && (_in_exec || _in_mem);
  assign dbus.req.write_en = _is_store && (_in_exec || _in_mem);
  assign _reg_write_en = _ctrl.reg_write_en && (_exec_done || (_mem_done && _is_load));

  always_ff @(posedge clk) begin
    if (rst) begin
      halted <= 1'b0;
    end else if (_illegal) begin
      halted <= 1'b1;
    end

    if (rst || _illegal || _in_halt) begin
      _current <= '0;
    end else begin
      if (_in_fetch && ibus.rsp.ready) begin
        _current.instr <= ibus.rsp.instr;
        _current.pc    <= ibus.req.addr;
      end else if (_retire) begin
        _current <= '0;
      end
    end

    if (rst) begin
      _state <= CORE_FETCH;
    end else begin
      _state <= _state_next;
    end
  end

  always_comb begin
    _state_next = _state;
    unique case (_state)
      CORE_FETCH: begin
        if (ibus.rsp.ready) begin
          _state_next = CORE_EXEC;
        end
      end
      CORE_EXEC: begin
        if (_illegal) begin
          _state_next = CORE_HALT;
        end else if (_is_mem_op && !dbus.rsp.ready) begin
          _state_next = CORE_MEM;
        end else begin
          _state_next = CORE_FETCH;
        end
      end
      CORE_MEM: begin
        if (dbus.rsp.ready) begin
          _state_next = CORE_FETCH;
        end
      end
      CORE_HALT: begin
        _state_next = CORE_HALT;
      end
    endcase
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
    .instr(_current.instr),
    .branch_flags(_branch_flags),
    .ctrl(_ctrl)
  );

  datapath _datapath (
    .clk(clk),
    .instr(_current.instr),
    .pc(_current.pc),
    .reg_write_en(_reg_write_en),
    .imm_format(_ctrl.imm_format),
    .alu_operands(_ctrl.alu_operands),
    .execute_result(_ctrl.execute_result),
    .alu_op(_ctrl.alu_op),
    .writeback_result(_ctrl.writeback_result),
    .sub_arith(_ctrl.sub_arith),
    .branch_sgnd(_ctrl.branch_sgnd),
    .read_data(_read_data),
    .ieu_addr(_raw_ieu_addr),
    .alu_result(dbus.req.addr),
    .write_data(_write_data),
    .branch_flags(_branch_flags)
  );

  logic _unused_csr_ctrl;
  assign _unused_csr_ctrl = |{_ctrl.csr_en, _ctrl.csr_write_en, _ctrl.csr_op, _ctrl.csr_use_zimm};

endmodule
