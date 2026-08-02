`timescale 1ns / 1ps

module core
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input clk,
  input rst,

  output logic halted,
  output pc_t  pc,

  ibus_if.master ibus,
  dbus_if.master dbus
);


  if_id_t        _if_id;
  id_ex_t        _id_ex;
  ex_mem_t       _ex_mem;
  mem_wb_t       _mem_wb;

  if_id_t        _if_id_next;
  id_ex_t        _id_ex_next;
  ex_mem_t       _ex_mem_next;
  mem_wb_t       _mem_wb_next;

  branch_flags_t _branch_flags;
  control_t      _ctrl;

  word_t         _decode_rs1_data;
  word_t         _decode_rs2_data;
  word_t         _decode_imm;
  word_t         _alu_result;
  word_t         _src_a;
  word_t         _src_b;
  word_t         _execute_result;
  word_t         _mem_read_data;
  word_t         _mem_result_data;
  logic          _mem_instr;
  logic          _mem_wait;
  logic          _pipe_en;
  if_id_t        _fetched;
  logic          _redirect_en;
  pc_t           _redirect_pc;
  logic          _data_stall;
  logic          _fetch_en;

  assign _src_a = _id_ex.ctrl.alu_src[1] ? _id_ex.pc : _id_ex.rs1_data;
  assign _src_b = _id_ex.ctrl.alu_src[0] ? _id_ex.imm : _id_ex.rs2_data;

  assign _mem_instr = _ex_mem.valid && (_ex_mem.ctrl.mem_write_en || _ex_mem.ctrl.result_src == RESULT_MEM);
  assign _mem_wait = _mem_instr && !dbus.rsp.ready;
  assign _pipe_en = !_mem_wait && !halted;
  assign _fetch_en = _pipe_en && !_data_stall;

  assign dbus.req.valid    = _ex_mem.valid && (_ex_mem.ctrl.mem_write_en || _ex_mem.ctrl.result_src == RESULT_MEM);
  assign dbus.req.write_en = _ex_mem.ctrl.mem_write_en;
  assign dbus.req.addr = _ex_mem.alu_result;

  assign _redirect_en = _id_ex.valid && (_id_ex.ctrl.pc_src != PC_SRC_INC);
  assign _redirect_pc = _id_ex.ctrl.clear_pc_lsb ? {_alu_result[31:1], 1'b0} : _alu_result;

  reg_file _reg_file (
    .clk(clk),
    .rd_addr1(_if_id.instr.r.rs1),
    .rd_addr2(_if_id.instr.r.rs2),
    .wr_addr(_mem_wb.rd),
    .wr_data(_mem_wb.result),
    .wr_en(_mem_wb.valid && _mem_wb.ctrl.reg_write_en),
    .rd_data1(_decode_rs1_data),
    .rd_data2(_decode_rs2_data)
  );

  ifu_pipelined _ifu_pipelined (
    .clk(clk),
    .rst(rst),
    .fetch_en(_fetch_en),
    .redirect_en(_redirect_en),
    .redirect_pc(_redirect_pc),
    .pc(pc),
    .fetched(_fetched),
    .ibus(ibus)
  );

  controller _controller (
    .instr       (_if_id.instr),
    .branch_flags(_branch_flags),
    .ctrl        (_ctrl)
  );

  extend _extend (
    .imm_src(_ctrl.imm_src),
    .instr  (_if_id.instr[31:7]),
    .imm_ext(_decode_imm)
  );

  comparator _comparator (
    .src_a(_decode_rs1_data),
    .src_b(_decode_rs2_data),
    .sngd(_ctrl.branch_sgnd),
    .eq(_branch_flags.eq),
    .lt(_branch_flags.lt)
  );

  alu _alu (
    .src_a(_src_a),
    .src_b(_src_b),
    .alu_select(_id_ex.ctrl.alu_select),
    .sub_arith(_id_ex.ctrl.sub_arith),
    .alu_result(_alu_result)
  );

  execute_result_mux _execute_result_mux (
    .alu_result_src(_id_ex.ctrl.alu_result_src),
    .pc(_id_ex.pc),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .execute_result(_execute_result)
  );

  lsu _lsu (
    .addr(_ex_mem.alu_result),
    .write_data(_ex_mem.write_data),
    .mem_size(_ex_mem.ctrl.mem_size),
    .mem_unsigned(_ex_mem.ctrl.mem_unsigned),
    .read_data(_mem_read_data),
    .mem_write_data(dbus.req.write_data),
    .mem_read_data(dbus.rsp.read_data),
    .write_mask(dbus.req.write_mask)
  );

  writeback_mux _mem_result_mux (
    .result_src(_ex_mem.ctrl.result_src),
    .execute_result(_ex_mem.execute_result),
    .read_data(_mem_read_data),
    .writeback_data(_mem_result_data)
  );

  hazard_unit _hazard_unit (
    .if_id_valid(_if_id.valid),
    .if_id_instr(_if_id.instr),
    .id_ex_valid(_id_ex.valid),
    .id_ex_reg_write_en(_id_ex.ctrl.reg_write_en),
    .id_ex_rd(_id_ex.rd),
    .ex_mem_valid(_ex_mem.valid),
    .ex_mem_reg_write_en(_ex_mem.ctrl.reg_write_en),
    .ex_mem_rd(_ex_mem.rd),
    .mem_wb_valid(_mem_wb.valid),
    .mem_wb_reg_write_en(_mem_wb.ctrl.reg_write_en),
    .mem_wb_rd(_mem_wb.rd),
    .stall(_data_stall)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      halted  <= 1'b0;
      _if_id  <= '0;
      _id_ex  <= '0;
      _ex_mem <= '0;
      _mem_wb <= '0;
    end else if (_if_id.valid && _ctrl.illegal_instr) begin
      halted <= 1'b1;
    end else begin
      _if_id  <= _if_id_next;
      _id_ex  <= _id_ex_next;
      _ex_mem <= _ex_mem_next;
      _mem_wb <= _mem_wb_next;
    end
  end

  always_comb begin
    if (!_pipe_en) begin
      _if_id_next  = _if_id;
      _id_ex_next  = _id_ex;
      _ex_mem_next = _ex_mem;
      _mem_wb_next = _mem_wb;
    end else begin
      _if_id_next  = '0;
      _id_ex_next  = '0;
      _ex_mem_next = '0;
      _mem_wb_next = '0;

      if (_redirect_en) begin
        _if_id_next = '0;
      end else if (_data_stall) begin
        _if_id_next = _if_id;
      end else if (_fetched.valid) begin
        _if_id_next = _fetched;
      end

      if (_data_stall || _redirect_en) begin
        _id_ex_next = '0;
      end else if (_if_id.valid) begin
        _id_ex_next = '{
            valid: 1'b1,
            pc: _if_id.pc,
            instr: _if_id.instr,
            ctrl: _ctrl,
            rs1_data: _decode_rs1_data,
            rs2_data: _decode_rs2_data,
            imm: _decode_imm,
            rd: _if_id.instr.r.rd
        };
      end

      if (_id_ex.valid) begin
        _ex_mem_next = '{
            valid: 1'b1,
            pc: _id_ex.pc,
            ctrl: _id_ex.ctrl,
            alu_result: _alu_result,
            execute_result: _execute_result,
            write_data: _id_ex.rs2_data,
            rd: _id_ex.instr.r.rd
        };
      end

      if (_ex_mem.valid) begin
        _mem_wb_next = '{
            valid: 1'b1,
            ctrl: _ex_mem.ctrl,
            result: _mem_result_data,
            rd: _ex_mem.rd
        };
      end
    end
  end

  pc_t _unused_pc;
  assign _unused_pc = _ex_mem.pc;

endmodule
