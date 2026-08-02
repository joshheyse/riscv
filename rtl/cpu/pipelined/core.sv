`timescale 1ns / 1ps

// Five-stage RV32I pipeline core.
//
// Stage boundaries:
// - IF/ID: instruction and request PC captured from the instruction fetch unit.
// - ID/EX: decoded control, register operands, immediate, and destination.
// - EX/MEM: ALU/execute result plus store data and memory controls.
// - MEM/WB: final writeback data and destination register.
//
// Control policy:
// - `_mem_wait` holds every pipeline register while a data-bus transaction is
//   outstanding.
// - `_data_stall` freezes fetch/decode and injects a bubble into execute.
// - `_redirect_en` flushes the fetched/decode-side wrong-path instruction and
//   redirects the IFU to the branch or jump target.
//
// This core resolves control flow in execute and forwards ALU/writeback results
// into execute operands. Load-use hazards still stall because load data is not
// available from EX/MEM.
//
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

  branch_flags_t _decode_branch_flags;
  branch_flags_t _execute_branch_flags;
  control_t      _ctrl;

  word_t         _decode_rs1_data;
  word_t         _decode_rs2_data;
  word_t         _decode_rs1_value;
  word_t         _decode_rs2_value;
  word_t         _decode_imm;
  word_t         _alu_result;
  word_t         _src_a;
  word_t         _src_b;
  word_t         _rs1_value;
  word_t         _rs2_value;
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
  logic          _unused_mem_wait;
  logic          _execute_branch;
  logic          _execute_jump;
  pc_src_t       _execute_pc_src;


  logic          _ex_mem_can_forward;
  logic          _mem_wb_can_forward;

  assign dbus.req.valid = _mem_instr;
  assign dbus.req.write_en = _ex_mem.ctrl.mem_write_en;
  assign dbus.req.addr = _ex_mem.alu_result;
  assign _unused_mem_wait = _mem_wait;
  assign _decode_branch_flags = '0;
  assign _execute_branch = _id_ex.instr.r.opcode == OP_BRANCH;
  assign _execute_jump = (_id_ex.instr.r.opcode == OP_JAL) || (_id_ex.instr.r.opcode == OP_JALR);
  assign _ex_mem_can_forward = _ex_mem.valid && _ex_mem.ctrl.reg_write_en && (_ex_mem.rd != 5'd0) && (_ex_mem.ctrl.result_src != RESULT_MEM);
  assign _mem_wb_can_forward = _mem_wb.valid && _mem_wb.ctrl.reg_write_en && (_mem_wb.rd != 5'd0);

  // Forwarding
  always_comb begin
    _rs1_value = _id_ex.rs1_data;
    _rs2_value = _id_ex.rs2_data;

    if (_ex_mem_can_forward && (_ex_mem.rd == _id_ex.instr.r.rs1)) begin
      _rs1_value = _ex_mem.execute_result;
    end else if (_mem_wb_can_forward && (_mem_wb.rd == _id_ex.instr.r.rs1)) begin
      _rs1_value = _mem_wb.result;
    end

    if (_ex_mem_can_forward && (_ex_mem.rd == _id_ex.instr.r.rs2)) begin
      _rs2_value = _ex_mem.execute_result;
    end else if (_mem_wb_can_forward && (_mem_wb.rd == _id_ex.instr.r.rs2)) begin
      _rs2_value = _mem_wb.result;
    end

    _src_a = _id_ex.ctrl.alu_src[1] ? _id_ex.pc : _rs1_value;
    _src_b = _id_ex.ctrl.alu_src[0] ? _id_ex.imm : _rs2_value;
  end

  always_comb begin
    _decode_rs1_value = _decode_rs1_data;
    _decode_rs2_value = _decode_rs2_data;

    if (_mem_wb_can_forward && (_mem_wb.rd == _if_id.instr.r.rs1)) begin
      _decode_rs1_value = _mem_wb.result;
    end

    if (_mem_wb_can_forward && (_mem_wb.rd == _if_id.instr.r.rs2)) begin
      _decode_rs2_value = _mem_wb.result;
    end
  end

  // Pipeline control
  pipeline_control _pipeline_control (
    .halted(halted),
    .ex_mem_valid(_ex_mem.valid),
    .ex_mem_mem_write_en(_ex_mem.ctrl.mem_write_en),
    .ex_mem_result_src(_ex_mem.ctrl.result_src),
    .dbus_ready(dbus.rsp.ready),
    .data_stall(_data_stall),
    .mem_instr(_mem_instr),
    .mem_wait(_mem_wait),
    .pipe_en(_pipe_en),
    .fetch_en(_fetch_en)
  );

  redirect_control _redirect_control (
    .id_ex_valid(_id_ex.valid),
    .id_ex_pc_src(_execute_pc_src),
    .id_ex_clear_pc_lsb(_id_ex.ctrl.clear_pc_lsb),
    .alu_result(_alu_result),
    .redirect_en(_redirect_en),
    .redirect_pc(_redirect_pc)
  );

  // Fetch
  always_comb begin
    if (!_pipe_en) begin
      _if_id_next = _if_id;
    end else begin
      _if_id_next = '0;

      if (_redirect_en) begin
        _if_id_next = '0;
      end else if (_data_stall) begin
        _if_id_next = _if_id;
      end else if (_fetched.valid) begin
        _if_id_next = _fetched;
      end
    end
  end

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .fetch_en(_fetch_en),
    .redirect_en(_redirect_en),
    .redirect_pc(_redirect_pc),
    .pc(pc),
    .fetched(_fetched),
    .ibus(ibus)
  );

  // Decode
  always_comb begin
    if (!_pipe_en) begin
      _id_ex_next = _id_ex;
    end else begin
      _id_ex_next = '0;

      if (_data_stall || _redirect_en) begin
        _id_ex_next = '0;
      end else if (_if_id.valid) begin
        _id_ex_next = '{
            valid: 1'b1,
            pc: _if_id.pc,
            instr: _if_id.instr,
            ctrl: _ctrl,
            rs1_data: _decode_rs1_value,
            rs2_data: _decode_rs2_value,
            imm: _decode_imm,
            rd: _if_id.instr.r.rd
        };
      end
    end
  end

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

  controller _controller (
    .instr       (_if_id.instr),
    .branch_flags(_decode_branch_flags),
    .ctrl        (_ctrl)
  );

  extend _extend (
    .imm_src(_ctrl.imm_src),
    .instr  (_if_id.instr[31:7]),
    .imm_ext(_decode_imm)
  );

  // Execute
  always_comb begin
    if (!_pipe_en) begin
      _ex_mem_next = _ex_mem;
    end else begin
      _ex_mem_next = '0;

      if (_id_ex.valid) begin
        _ex_mem_next = '{
            valid: 1'b1,
            pc: _id_ex.pc,
            ctrl: _id_ex.ctrl,
            alu_result: _alu_result,
            execute_result: _execute_result,
            write_data: _rs2_value,
            rd: _id_ex.instr.r.rd
        };
      end
    end
  end

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

  comparator _execute_comparator (
    .src_a(_rs1_value),
    .src_b(_rs2_value),
    .sngd(_id_ex.ctrl.branch_sgnd),
    .eq(_execute_branch_flags.eq),
    .lt(_execute_branch_flags.lt)
  );

  branch_logic _execute_branch_logic (
    .branch(_execute_branch),
    .jump(_execute_jump),
    .flags(_execute_branch_flags),
    .funct3(_id_ex.instr.r.funct3.br),
    .pc_src(_execute_pc_src)
  );

  // Memory
  always_comb begin
    if (!_pipe_en) begin
      _mem_wb_next = _mem_wb;
    end else begin
      _mem_wb_next = '0;

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

  // Writeback and hazards
  hazard_unit _hazard_unit (
    .if_id_valid(_if_id.valid),
    .if_id_instr(_if_id.instr),
    .id_ex_valid(_id_ex.valid),
    .id_ex_reg_write_en(_id_ex.ctrl.reg_write_en),
    .id_ex_rd(_id_ex.rd),
    .ex_mem_valid(_ex_mem.valid),
    .ex_mem_reg_write_en(_ex_mem.ctrl.reg_write_en),
    .ex_mem_rd(_ex_mem.rd),
    .ex_mem_result_src(_ex_mem.ctrl.result_src),
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

  pc_t _unused_pc;
  assign _unused_pc = _ex_mem.pc;

endmodule
