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
#(
  parameter mem_addr_t CacheableBase = '0,
  parameter mem_addr_t CacheableEnd  = '0
) (
  input clk,
  input rst,

  output logic halted,
  output pc_t  pc,

  mem_if.master mem,
  irq_if.sink   irq
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
  trap_stage_t    _trap;
  flow_ctrl_t     _flow;

  trap_req_t      _csr_illegal_trap_req;
  trap_req_t      _interrupt_trap_req;
  trap_req_t      _id_trap_req;
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
  logic           _trap_held;
  retire_ctrl_t   _retire;
  logic           _trap_from_if_id;
  logic           _ex_mret_valid;
  logic           _ex_sret_valid;


  mem_if _data_cache_arb ();
  mem_if _data_lsu_cache ();
  mem_if _ifetch_cache_arb ();
  mem_if _ifetch_ifu_cache ();

  assign _id_branch_flags = '0;

  assign _csr.addr.raw = _id_ex.slot.instr.i.imm.raw;  // bits [31:20]
  assign _csr.en = _id_ex.valid && _id_ex.ctrl.csr.en && !_id_ex.trap.valid;
  assign _csr.write_en = _id_ex.valid && _id_ex.ctrl.csr.write_en && !_id_ex.trap.valid;
  assign _csr_illegal = _csr.illegal || _csr_access_illegal;

  assign _retire.trap = _mem_wb.valid && _mem_wb.trap.valid;
  assign _retire.mret = _mem_wb.valid && (_mem_wb.ctrl.system.op == SYSTEM_OP_MRET) && !_mem_wb.trap.valid;
  assign _retire.sret = _mem_wb.valid && (_mem_wb.ctrl.system.op == SYSTEM_OP_SRET) && !_mem_wb.trap.valid;
  assign _ex_mret_valid = _id_ex.valid && _id_ex.ctrl.system.en &&
      (_id_ex.ctrl.system.op == SYSTEM_OP_MRET) && !_id_ex.trap.valid &&
      !_system_access_illegal;
  assign _ex_sret_valid = _id_ex.valid && _id_ex.ctrl.system.en &&
      (_id_ex.ctrl.system.op == SYSTEM_OP_SRET) && !_id_ex.trap.valid &&
      !_system_access_illegal;

  logic _mie_pending_meip;
  logic _mie_pending_mtip;
  logic _mie_pending_msip;
  logic _mie_pending_seip;
  logic _mie_pending_stip;
  logic _mie_pending_ssip;
  logic _machine_interrupts_enabled;
  logic _supervisor_interrupts_enabled;

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

  assign _trap_from_if_id = _if_id.valid && _id_trap.valid && !_trap_held;

  always_comb begin
    _interrupt_trap_req = '0;
    _mie_pending_meip = _csr_status.mip.meip | irq.pending.meip;
    _mie_pending_mtip = _csr_status.mip.mtip | irq.pending.mtip;
    _mie_pending_msip = _csr_status.mip.msip | irq.pending.msip;
    _mie_pending_seip = _csr_status.mip.seip | irq.pending.seip;
    _mie_pending_stip = _csr_status.mip.stip | irq.pending.stip;
    _mie_pending_ssip = _csr_status.mip.ssip | irq.pending.ssip;
    _machine_interrupts_enabled = (_csr_status.priv_mode != PRIV_MACHINE) ||
        _csr_status.mstatus.mie;
    _supervisor_interrupts_enabled = (_csr_status.priv_mode == PRIV_USER) ||
        ((_csr_status.priv_mode == PRIV_SUPERVISOR) && _csr_status.mstatus.sie);

    if (_csr_status.mie.meip && _mie_pending_meip && _machine_interrupts_enabled) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.mtip && _mie_pending_mtip && _machine_interrupts_enabled) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_TIMER_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.msip && _mie_pending_msip && _machine_interrupts_enabled) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_SOFTWARE_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.seip && _mie_pending_seip &&
                 (_csr_status.mideleg[9] ? _supervisor_interrupts_enabled :
                                          _machine_interrupts_enabled)) begin
      _interrupt_trap_req = '{
          valid: 1'b1,
          src: TRAP_SRC_SUPERVISOR_EXTERNAL_INTERRUPT,
          tval: '0
      };
    end else if (_csr_status.mie.stip && _mie_pending_stip &&
                 (_csr_status.mideleg[5] ? _supervisor_interrupts_enabled :
                                          _machine_interrupts_enabled)) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_SUPERVISOR_TIMER_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.ssip && _mie_pending_ssip &&
                 (_csr_status.mideleg[1] ? _supervisor_interrupts_enabled :
                                          _machine_interrupts_enabled)) begin
      _interrupt_trap_req = '{
          valid: 1'b1,
          src: TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT,
          tval: '0
      };
    end
  end

  always_comb begin
    _id_trap_req = _ctrl.trap;
    if (_if_id.valid && !_id_trap_req.valid) begin
      _id_trap_req = _interrupt_trap_req;
    end
  end

  assign _csr_illegal_trap_req = '{
          valid: _id_ex.valid && _id_ex.ctrl.csr.en && !_id_ex.trap.valid && _csr_illegal,
          src: TRAP_SRC_ILLEGAL_CSR,
          tval: _id_ex.slot.instr.raw
      };

  assign _system_illegal_trap_req = '{
          valid: _id_ex.valid && !_id_ex.trap.valid && _system_access_illegal,
          src: TRAP_SRC_ILLEGAL_INSTR,
          tval: _id_ex.slot.instr.raw
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
    .trap(_mem_wb.trap.payload),
    .mret_valid(_retire.mret),
    .sret_valid(_retire.sret),
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
    .tsr(_csr_status.mstatus.tsr),
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
    .trap_req(_id_trap_req),
    .pc(_if_id.slot.pc),
    .csr_status(_csr_status),
    .trap(_id_trap)
  );

  trap_control _ex_trap_control (
    .trap_req(_csr_illegal_trap_req),
    .pc(_id_ex.slot.pc),
    .csr_status(_csr_status),
    .trap(_csr_trap)
  );

  trap_control _system_trap_control (
    .trap_req(_system_illegal_trap_req),
    .pc(_id_ex.slot.pc),
    .csr_status(_csr_status),
    .trap(_system_trap)
  );

  trap_control _redirect_trap_control (
    .trap_req(_redirect_trap_req),
    .pc(_id_ex.slot.pc),
    .csr_status(_csr_status),
    .trap(_redirect_trap)
  );

  trap_orchestrator _trap_orchestrator (
    .clk(clk),
    .rst(rst),
    .id_trap((_if_id.valid && !_ex_mret_valid && !_ex_sret_valid) ? _id_trap : '0),
    .ex_trap(_id_ex.valid ? _ex_trap : '0),
    .mem_trap(_mem_wb.valid ? _mem_wb.trap : '0),
    .clear_trap(_retire.trap),
    .trap_held(_trap_held),
    .trap(_trap),
    .trap_in_flight(_trap_in_flight)
  );

  flow_control _flow_control (
    .redirect(_redirect),
    .trap(_trap),
    .mret_valid(_ex_mret_valid),
    .sret_valid(_ex_sret_valid),
    .mepc(_csr_status.mepc),
    .sepc(_csr_status.sepc),
    .flow(_flow)
  );

  pipeline_control _pipeline_control (
    .halted(halted),
    .mem_wait(_dbus_wait),
    .data_stall(_data_stall),
    .trap_from_if_id(_trap_from_if_id),
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

  mem_arbiter _mem_arbiter (
    .clk(clk),
    .rst(rst),
    .ifetch(_ifetch_cache_arb.slave),
    .data(_data_cache_arb.slave),
    .mem(mem)
  );

  l1_cache #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _l1i_cache (
    .clk(clk),
    .rst(rst),
    .upstream(_ifetch_ifu_cache.slave),
    .downstream(_ifetch_cache_arb.master)
  );

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .fetch_en(_pipe_ctrl.fetch == STAGE_ADVANCE),
    .redirect(_flow.redirect),
    .pc(pc),
    .fetched(_fetched),
    .ibus(_ifetch_ifu_cache.master)
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

  l1_cache #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _l1d_cache (
    .clk(clk),
    .rst(rst),
    .upstream(_data_lsu_cache.slave),
    .downstream(_data_cache_arb.master)
  );

  mem_stage _mem_stage (
    .ex_mem(_ex_mem),
    .csr_status(_csr_status),
    .mem_wait(_dbus_wait),
    .mem_wb_payload(_mem_wb_payload),
    .dbus(_data_lsu_cache.master)
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
