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
// - `_flow.redirect.valid` redirects the IFU to the priority-resolved trap,
//   branch, or jump target.
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


  if_id_t         _if_id;
  id_ex_t         _id_ex;
  ex_mem_t        _ex_mem;
  mem_wb_t        _mem_wb;

  if_id_t         _if_id_next;
  id_ex_t         _id_ex_next;
  ex_mem_t        _ex_mem_next;
  mem_wb_t        _mem_wb_next;

  branch_flags_t  _decode_branch_flags;
  control_t       _ctrl;

  reg_data_t      _rf_rs1_read;
  reg_data_t      _rf_rs2_read;
  reg_data_t      _id_rs1_operand;
  reg_data_t      _id_rs2_operand;

  imm_t           _decode_imm;
  alu_data_t      _alu_result;
  branch_flags_t  _execute_branch_flags;
  reg_data_t      _ex_rs1_operand;
  reg_data_t      _ex_rs2_operand;
  mem_data_t      _store_data;
  reg_data_t      _execute_result;
  if_id_t         _fetched;
  logic           _data_stall;
  pc_src_t        _execute_pc_src;

  logic           _mem_wait;
  mem_wb_t        _mem_wb_payload;

  redirect_t      _redirect;
  trap_t          _trap;
  flow_ctrl_t     _flow;

  csr_pipe_t      _csr;
  mtvec_t         _mtvec;

  pipeline_ctrl_t _pipe_ctrl;

  assign _mtvec = '0;

  assign _decode_branch_flags = '0;

  assign _csr.en = _id_ex.valid && _id_ex.ctrl.csr_en;
  assign _csr.addr = _id_ex.instr.i.imm;  // bits [31:20]
  assign _csr.write_en = _id_ex.valid && _id_ex.ctrl.csr_write_en;

  // Files
  reg_file _reg_file (
    .clk(clk),
    .rd_addr1(_if_id.instr.r.rs1),
    .rd_addr2(_if_id.instr.r.rs2),
    .wr_addr(_mem_wb.rd),
    .wr_data(_mem_wb.result),
    .wr_en(_mem_wb.valid && _mem_wb.ctrl.reg_write_en),
    .rd_data1(_rf_rs1_read),
    .rd_data2(_rf_rs2_read)
  );

  csr_file _csr_file (
    .clk(clk),
    .rst(rst),
    .csr_en(_csr.en),
    .csr_write_en(_csr.write_en),
    .csr_addr(_csr.addr),
    .csr_write_data(_csr.write_data),
    .trap_valid(_trap.valid),
    .trap_mepc(_trap.mepc),
    .trap_mcause(_trap.mcause),
    .trap_mtval(_trap.mtval),
    .csr_read_data(_csr.read_data),
    .illegal_csr(_csr.illegal)
  );

  // Pipeline control
  redirect_control _redirect_control (
    .id_ex_valid(_id_ex.valid),
    .id_ex_pc_src(_execute_pc_src),
    .id_ex_clear_pc_lsb(_id_ex.ctrl.clear_pc_lsb),
    .alu_result(_alu_result),
    .redirect(_redirect)
  );

  trap_control _trap_control (
    .illegal_instr(_if_id.valid && _ctrl.illegal_instr),
    .instr(_if_id.instr),
    .pc(_if_id.pc),
    .mtvec(_mtvec),
    .trap(_trap)
  );

  flow_control _flow_control (
    .redirect(_redirect),
    .trap(_trap),
    .flow(_flow)
  );

  pipeline_control _pipeline_control (
    .halted(halted),
    .mem_wait(_mem_wait),
    .data_stall(_data_stall),
    .flow(_flow),
    .pipe_ctrl(_pipe_ctrl)
  );

  // Fetch
  always_comb begin
    _if_id_next = '0;

    unique case (_pipe_ctrl.if_id)
      STAGE_HOLD: begin
        _if_id_next = _if_id;
      end

      STAGE_FLUSH: begin
        _if_id_next = '0;
      end

      STAGE_ADVANCE: begin
        if (_redirect.valid) begin
          _if_id_next = '0;
        end else if (_fetched.valid) begin
          _if_id_next = _fetched;
        end
      end
    endcase
  end

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .fetch_en(_pipe_ctrl.fetch == STAGE_ADVANCE),
    .redirect(_flow.redirect),
    .pc(pc),
    .fetched(_fetched),
    .ibus(ibus)
  );

  // Decode
  always_comb begin
    _id_ex_next = '0;

    unique case (_pipe_ctrl.id_ex)
      STAGE_HOLD: begin
        _id_ex_next = _id_ex;
      end

      STAGE_FLUSH: begin
        _id_ex_next = '0;
      end

      STAGE_ADVANCE: begin
        if (_redirect.valid) begin
          _id_ex_next = '0;
        end else if (_if_id.valid) begin
          _id_ex_next = '{
              valid: 1'b1,
              pc: _if_id.pc,
              instr: _if_id.instr,
              ctrl: _ctrl,
              rs1_operand: _id_rs1_operand,
              rs2_operand: _id_rs2_operand,
              imm: _decode_imm,
              rd: _if_id.instr.r.rd
          };
        end
      end
    endcase
  end

  controller _controller (
    .instr(_if_id.instr),
    .branch_flags(_decode_branch_flags),
    .ctrl(_ctrl)
  );

  extend _extend (
    .imm_format(_ctrl.imm_format),
    .instr(_if_id.instr[31:7]),
    .imm_ext(_decode_imm)
  );

  // Execute
  always_comb begin
    _ex_mem_next = '0;

    unique case (_pipe_ctrl.ex_mem)
      STAGE_HOLD: begin
        _ex_mem_next = _ex_mem;
      end

      STAGE_FLUSH: begin
        _ex_mem_next = '0;
      end

      STAGE_ADVANCE: begin
        if (_id_ex.valid) begin
          _ex_mem_next = '{
              valid: 1'b1,
              pc: _id_ex.pc,
              ctrl: _id_ex.ctrl,
              alu_result: _alu_result,
              execute_result: _execute_result,
              write_data: _store_data,
              rd: _id_ex.instr.r.rd
          };
        end
      end
    endcase
  end

  integer_execute _integer_execute (
    .ctrl(_id_ex.ctrl),
    .branch_funct3(_id_ex.instr.r.funct3.br),
    .pc(_id_ex.pc),
    .rs1_data(_ex_rs1_operand),
    .rs2_data(_ex_rs2_operand),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .store_data(_store_data),
    .branch_flags(_execute_branch_flags),
    .pc_src(_execute_pc_src)
  );

  csr_execute _csr_execute (
    .csr_op(_id_ex.ctrl.csr_op),
    .csr_use_zimm(_id_ex.ctrl.csr_use_zimm),
    .csr_read_data(_csr.read_data),
    .rs1_data(_ex_rs1_operand),
    .zimm(_id_ex.instr.r.rs1),
    .csr_result(_csr.result),
    .csr_write_data(_csr.write_data)
  );

  execute_result_mux _execute_result_mux (
    .execute_result_kind(_id_ex.ctrl.execute_result),
    .pc(_id_ex.pc),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .csr_result(_csr.result),
    .execute_result(_execute_result)
  );

  // Memory
  always_comb begin
    _mem_wb_next = '0;

    unique case (_pipe_ctrl.mem_wb)
      STAGE_HOLD: begin
        _mem_wb_next = _mem_wb;
      end

      STAGE_FLUSH: begin
        _mem_wb_next = '0;
      end

      STAGE_ADVANCE: begin
        _mem_wb_next = _mem_wb_payload;
      end
    endcase
  end

  mem_stage _mem_stage (
    .ex_mem(_ex_mem),
    .mem_wait(_mem_wait),
    .mem_wb_payload(_mem_wb_payload),
    .dbus(dbus)
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
    .ex_mem_writeback_result(_ex_mem.ctrl.writeback_result),
    .stall(_data_stall)
  );

  forwarding_unit _forwarding_unit (
    .id_ex(_id_ex),
    .ex_mem(_ex_mem),
    .mem_wb(_mem_wb),
    .rs1_operand(_ex_rs1_operand),
    .rs2_operand(_ex_rs2_operand)
  );

  decode_bypass_unit _decode_bypass_unit (
    .if_id(_if_id),
    .mem_wb(_mem_wb),
    .rf_rs1_read(_rf_rs1_read),
    .rf_rs2_read(_rf_rs2_read),
    .id_rs1_operand(_id_rs1_operand),
    .id_rs2_operand(_id_rs2_operand)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      halted  <= 1'b0;
      _if_id  <= '0;
      _id_ex  <= '0;
      _ex_mem <= '0;
      _mem_wb <= '0;
    end else if (_trap.valid) begin
      halted  <= 1'b1;
      _if_id  <= '0;
      _id_ex  <= '0;
      _ex_mem <= '0;
      _mem_wb <= '0;
    end else begin
      _if_id  <= _if_id_next;
      _id_ex  <= _id_ex_next;
      _ex_mem <= _ex_mem_next;
      _mem_wb <= _mem_wb_next;
    end
  end

  pc_t _unused_pc;
  assign _unused_pc = _ex_mem.pc;

  logic _unused_csr;
  assign _unused_csr = |{_csr.read_data, _csr.illegal, _trap.pc};

  logic _unused_execute_branch_flags;
  assign _unused_execute_branch_flags = |{_execute_branch_flags};

endmodule
