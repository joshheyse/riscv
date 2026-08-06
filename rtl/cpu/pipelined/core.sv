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
// - `_dbus_wait` holds every pipeline register while a data-bus transaction is
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

  branch_flags_t  _id_branch_flags;
  control_t       _ctrl;

  reg_data_t      _rf_rs1_read;
  reg_data_t      _rf_rs2_read;
  reg_data_t      _id_rs1_operand;
  reg_data_t      _id_rs2_operand;

  imm_t           _id_imm;
  alu_data_t      _alu_result;
  reg_data_t      _ex_rs1_operand;
  reg_data_t      _ex_rs2_operand;
  mem_data_t      _store_data;
  reg_data_t      _ex_result;
  if_id_t         _fetched;
  logic           _data_stall;
  pc_src_t        _ex_pc_src;

  logic           _dbus_wait;
  mem_wb_t        _mem_wb_payload;

  redirect_t      _redirect;
  trap_stage_t    _id_trap;
  trap_stage_t    _csr_trap;
  trap_stage_t    _system_trap;
  trap_stage_t    _redirect_trap;
  trap_stage_t    _ex_trap;
  /* verilator lint_off UNUSEDSIGNAL */
  trap_stage_t    _active_trap;
  /* verilator lint_on UNUSEDSIGNAL */
  flow_ctrl_t     _flow;

  trap_req_t      _csr_illegal_trap_req;
  trap_req_t      _system_illegal_trap_req;
  trap_req_t      _redirect_trap_req;
  logic           _csr_access_illegal;
  logic           _system_access_illegal;
  logic           _csr_illegal;

  /* verilator lint_off UNUSEDSIGNAL */
  csr_pipe_t      _csr;
  csr_status_t    _csr_status;
  /* verilator lint_on UNUSEDSIGNAL */

  pipeline_ctrl_t _pipe_ctrl;
  logic           _trap_in_flight;
  retire_ctrl_t   _retire;

  assign _id_branch_flags = '0;

  assign _csr.addr.raw = _id_ex.slot.instr.i.imm.raw;  // bits [31:20]
  assign _csr.en = _id_ex.valid && _id_ex.ctrl.csr.en && !_id_ex.trap.valid;
  assign _csr.write_en = _id_ex.valid && _id_ex.ctrl.csr.write_en && !_id_ex.trap.valid;
  assign _csr_illegal = _csr.illegal || _csr_access_illegal;

  assign _retire.trap = _mem_wb.valid && _mem_wb.trap.valid;
  assign _retire.mret = _mem_wb.valid && (_mem_wb.ctrl.system.op == SYSTEM_OP_MRET) && !_mem_wb.trap.valid;
  always_comb begin
    _ex_trap = '0;

    if (_id_ex.trap.valid) begin
      _ex_trap = _id_ex.trap;
    end else if (_redirect_trap.valid) begin
      _ex_trap = _redirect_trap;
    end else if (_csr_trap.valid) begin
      _ex_trap = _csr_trap;
    end else if (_system_trap.valid) begin
      _ex_trap = _system_trap;
      end
  end

  trap_orchestrator _trap_orchestrator (
    .clk(clk),
    .rst(rst),
    .id_trap(_if_id.valid ? _id_trap : '0),
    .ex_trap(_id_ex.valid ? _ex_trap : '0),
    .mem_trap(_mem_wb.valid ? _mem_wb.trap : '0),
    .clear_trap(_retire.trap),
    .trap(_active_trap),
    .trap_in_flight(_trap_in_flight)
  );

  assign _csr_illegal_trap_req = '{
          valid: _id_ex.valid && _id_ex.ctrl.csr.en && !_id_ex.trap.valid && _csr_illegal,
          src: TRAP_SRC_ILLEGAL_CSR,
          mtval: _id_ex.slot.instr.raw
      };

  assign _system_illegal_trap_req = '{
          valid: _id_ex.valid && !_id_ex.trap.valid && _system_access_illegal,
          src: TRAP_SRC_ILLEGAL_INSTR,
          mtval: _id_ex.slot.instr.raw
      };

  // Files
  reg_file _reg_file (
    .clk(clk),
    .rd_addr1(_if_id.slot.instr.r.rs1),
    .rd_addr2(_if_id.slot.instr.r.rs2),
    .wr_addr(_mem_wb.rd),
    .wr_data(_mem_wb.result),
    .wr_en(_mem_wb.valid && _mem_wb.ctrl.reg_write_en && !_mem_wb.trap.valid),
    .rd_data1(_rf_rs1_read),
    .rd_data2(_rf_rs2_read)
  );

  csr_file _csr_file (
    .clk(clk),
    .rst(rst),
    .csr_en(_csr.en),
    .csr_write_en(_csr.write_en && !_csr_access_illegal),
    .csr_addr(_csr.addr),
    .csr_write_data(_csr.write_data),
    .trap_valid(_retire.trap),
    .trap_mepc(_mem_wb.trap.payload.mepc),
    .trap_mcause(_mem_wb.trap.payload.mcause),
    .trap_mtval(_mem_wb.trap.payload.mtval),
    .mret_valid(_retire.mret),
    .csr_read_data(_csr.read_data),
    .illegal_csr(_csr.illegal),
    .status(_csr_status)
  );

  csr_access_control _csr_access_control (
    .csr_en(_csr.en),
    .csr_write_en(_csr.write_en),
    .csr_addr(_csr.addr),
    .priv_mode(_csr_status.priv_mode),
    .illegal_csr_access(_csr_access_illegal)
  );

  system_access_control _system_access_control (
    .system_ctrl(_id_ex.ctrl.system),
    .priv_mode(_csr_status.priv_mode),
    .illegal_system_access(_system_access_illegal)
  );

  // Pipeline control
  redirect_control _redirect_control (
    .id_ex_valid(_id_ex.valid),
    .id_ex_pc_src(_ex_pc_src),
    .id_ex_clear_pc_lsb(_id_ex.ctrl.clear_pc_lsb),
    .alu_result(_alu_result),
    .redirect(_redirect),
    .trap(_redirect_trap_req)
  );

  trap_control _id_trap_control (
    .trap_req(_ctrl.trap),
    .pc(_if_id.slot.pc),
    .mtvec(_csr_status.mtvec),
    .priv_mode(_csr_status.priv_mode),
    .trap(_id_trap)
  );

  trap_control _ex_trap_control (
    .trap_req(_csr_illegal_trap_req),
    .pc(_id_ex.slot.pc),
    .mtvec(_csr_status.mtvec),
    .priv_mode(_csr_status.priv_mode),
    .trap(_csr_trap)
  );

  trap_control _system_trap_control (
    .trap_req(_system_illegal_trap_req),
    .pc(_id_ex.slot.pc),
    .mtvec(_csr_status.mtvec),
    .priv_mode(_csr_status.priv_mode),
    .trap(_system_trap)
  );

  trap_control _redirect_trap_control (
    .trap_req(_redirect_trap_req),
    .pc(_id_ex.slot.pc),
    .mtvec(_csr_status.mtvec),
    .priv_mode(_csr_status.priv_mode),
    .trap(_redirect_trap)
  );

  flow_control _flow_control (
    .redirect(_redirect),
    .trap(_mem_wb.trap),
    .mret_valid(_retire.mret),
    .mepc(_csr_status.mepc),
    .flow(_flow)
  );

  pipeline_control _pipeline_control (
    .halted(halted),
    .mem_wait(_dbus_wait),
    .data_stall(_data_stall),
    .trap_in_flight(_trap_in_flight),
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
        if (_fetched.valid) begin
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
        if (_if_id.valid) begin
          _id_ex_next = '{
              valid: 1'b1,
              slot: _if_id.slot,
              ctrl: _ctrl,
              rs1_operand: _id_rs1_operand,
              rs2_operand: _id_rs2_operand,
              imm: _id_imm,
              trap: _id_trap
          };
        end
      end
    endcase
  end

  controller _controller (
    .instr(_if_id.slot.instr),
    .branch_flags(_id_branch_flags),
    .ctrl(_ctrl)
  );

  extend _extend (
    .imm_format(_ctrl.imm_format),
    .instr(_if_id.slot.instr[31:7]),
    .imm_ext(_id_imm)
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
              pc: _id_ex.slot.pc,
              ctrl: _id_ex.ctrl,
              alu_result: _alu_result,
              execute_result: _ex_result,
              write_data: _store_data,
              rd: _id_ex.slot.instr.r.rd,
              trap: _ex_trap
          };
        end
      end
    endcase
  end

  integer_execute _integer_execute (
    .ctrl(_id_ex.ctrl),
    .branch_funct3(_id_ex.slot.instr.r.funct3.br),
    .pc(_id_ex.slot.pc),
    .rs1_data(_ex_rs1_operand),
    .rs2_data(_ex_rs2_operand),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .store_data(_store_data),
    .pc_src(_ex_pc_src)
  );

  csr_execute _csr_execute (
    .csr_op(_id_ex.ctrl.csr.op),
    .csr_use_zimm(_id_ex.ctrl.csr.use_zimm),
    .csr_read_data(_csr.read_data),
    .rs1_data(_ex_rs1_operand),
    .zimm(_id_ex.slot.instr.r.rs1),
    .csr_result(_csr.result),
    .csr_write_data(_csr.write_data)
  );

  execute_result_mux _execute_result_mux (
    .execute_result_kind(_id_ex.ctrl.execute_result),
    .pc(_id_ex.slot.pc),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .csr_result(_csr.result),
    .execute_result(_ex_result)
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
    .mtvec(_csr_status.mtvec),
    .priv_mode(_csr_status.priv_mode),
    .mem_wait(_dbus_wait),
    .mem_wb_payload(_mem_wb_payload),
    .dbus(dbus)
  );

  // Writeback and hazards
  hazard_unit _hazard_unit (
    .if_id (_if_id),
    .id_ex (_id_ex),
    .ex_mem(_ex_mem),
    .stall (_data_stall)
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
    end else begin
      _if_id  <= _if_id_next;
      _id_ex  <= _id_ex_next;
      _ex_mem <= _ex_mem_next;
      _mem_wb <= _mem_wb_next;
    end
  end

endmodule
