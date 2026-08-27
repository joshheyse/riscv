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
  input dword_t time_value,

  output logic halted,
  output pc_t  pc,

  mem_if.master mem,
  irq_if.sink   irq
);


  if_id_t           _if_id;
  id_ex_t           _id_ex;
  ex_mem_t          _ex_mem;
  mem_wb_t          _mem_wb;

  branch_flags_t    _id_branch_flags;
  control_t         _ctrl;

  reg_data_t        _rf_rs1_read;
  reg_data_t        _rf_rs2_read;
  reg_data_t        _id_rs1_operand;
  reg_data_t        _id_rs2_operand;

  imm_t             _id_imm;
  integer_data_t    _alu_result;
  reg_data_t        _ex_rs1_operand;
  reg_data_t        _ex_rs2_operand;
  mem_data_t        _store_data;
  reg_data_t        _ex_result;
  if_id_t           _fetched;
  logic             _data_stall;
  logic             _execute_wait;
  pc_src_t          _ex_pc_src;

  logic             _dbus_wait;
  mem_wb_t          _mem_wb_payload;

  redirect_t        _execute_redirect;
  redirect_t        _mem_order_redirect;
  trap_stage_t      _id_trap;
  trap_stage_t      _csr_trap;
  trap_stage_t      _system_trap;
  trap_stage_t      _redirect_trap;
  trap_stage_t      _ex_trap;
  trap_stage_t      _trap;
  flow_ctrl_t       _flow;

  trap_req_t        _csr_illegal_trap_req;
  trap_req_t        _interrupt_trap_req;
  trap_req_t        _id_trap_req;
  trap_req_t        _system_illegal_trap_req;
  trap_req_t        _redirect_trap_req;
  logic             _csr_access_illegal;
  logic             _system_access_illegal;
  logic             _csr_illegal;

  /* verilator lint_off UNUSEDSIGNAL */
  csr_pipe_t        _csr;
  csr_status_t      _csr_status;
  /* verilator lint_on UNUSEDSIGNAL */

  pipeline_ctrl_t   _pipe_ctrl;
  logic             _trap_in_flight;
  logic             _trap_from_id;
  // Retained as an observable for the trap_orchestrator testbench; the
  // pipeline decision now uses `_trap_from_id` instead.
  /* verilator lint_off UNUSEDSIGNAL */
  logic             _trap_held;
  /* verilator lint_on UNUSEDSIGNAL */
  retire_ctrl_t     _retire;
  logic             _trap_from_if_id;
  logic             _ex_mret_valid;
  logic             _ex_sret_valid;

  logic             _mem_order_busy;
  logic             _mem_order_start;

  translation_ctx_t _ifetch_translation_ctx;
  translation_ctx_t _data_translation_ctx;

  vmem_if _ifetch_ifu_adapter (
    clk,
    rst
  );
  vmem_if _data_lsu_adapter (
    clk,
    rst
  );
  mmu_if _ifetch_translation ();
  mmu_if _data_translation ();

  mem_if _data_cache_arb (
    clk,
    rst
  );
  mem_if _data_lsu_cache (
    clk,
    rst
  );
  mem_if _data_adapter_arb (
    clk,
    rst
  );
  mem_if _data_walker_arb (
    clk,
    rst
  );
  mem_if _physical_mem (
    clk,
    rst
  );
  mem_if _ifetch_cache_arb (
    clk,
    rst
  );
  mem_if _ifetch_ifu_cache (
    clk,
    rst
  );
  mem_if _ifetch_adapter_arb (
    clk,
    rst
  );
  mem_if _ifetch_walker_arb (
    clk,
    rst
  );

  cache_command_if _dcache_command ();
  cache_command_if _icache_command ();

  assign _id_branch_flags = '0;

  assign _ifetch_translation_ctx = '{
          access : MMU_ACCESS_FETCH,
          privilege: _csr_status.priv_mode,
          sum: _csr_status.mstatus.sum,
          mxr: _csr_status.mstatus.mxr
      };
  assign _data_translation_ctx = '{
          access : _data_lsu_adapter.req.write_en ? MMU_ACCESS_STORE : MMU_ACCESS_LOAD,
          privilege: _csr_status.priv_mode,
          sum: _csr_status.mstatus.sum,
          mxr: _csr_status.mstatus.mxr
      };

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
  logic _machine_interrupts_en;
  logic _supervisor_interrupts_en;

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

  // The trapping instruction must reach ID/EX to retire its trap. Asking
  // whether the trap is *unheld* is wrong: a trap raised during a memory wait
  // is latched cycles before the pipeline may move, and would then be flushed
  // and lost. Ask instead whether the in-flight trap is the one in decode.
  assign _trap_from_if_id = _if_id.valid && _trap_from_id;

  always_comb begin
    _interrupt_trap_req = '0;
    _mie_pending_meip = _csr_status.mip.meip | irq.pending.meip;
    _mie_pending_mtip = _csr_status.mip.mtip | irq.pending.mtip;
    _mie_pending_msip = _csr_status.mip.msip | irq.pending.msip;
    _mie_pending_seip = _csr_status.mip.seip | irq.pending.seip;
    _mie_pending_stip = _csr_status.mip.stip | irq.pending.stip;
    _mie_pending_ssip = _csr_status.mip.ssip | irq.pending.ssip;
    _machine_interrupts_en = (_csr_status.priv_mode != PRIV_MACHINE) || _csr_status.mstatus.mie;
    _supervisor_interrupts_en = (_csr_status.priv_mode == PRIV_USER) ||
        ((_csr_status.priv_mode == PRIV_SUPERVISOR) && _csr_status.mstatus.sie);

    if (_csr_status.mie.meip && _mie_pending_meip && _machine_interrupts_en) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_EXTERNAL_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.mtip && _mie_pending_mtip && _machine_interrupts_en) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_TIMER_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.msip && _mie_pending_msip && _machine_interrupts_en) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_MACHINE_SOFTWARE_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.seip && _mie_pending_seip &&
                 (_csr_status.mideleg[9] ? _supervisor_interrupts_en :
                                          _machine_interrupts_en)) begin
      _interrupt_trap_req = '{
          valid: 1'b1,
          src: TRAP_SRC_SUPERVISOR_EXTERNAL_INTERRUPT,
          tval: '0
      };
    end else if (_csr_status.mie.stip && _mie_pending_stip &&
                 (_csr_status.mideleg[5] ? _supervisor_interrupts_en :
                                          _machine_interrupts_en)) begin
      _interrupt_trap_req = '{valid: 1'b1, src: TRAP_SRC_SUPERVISOR_TIMER_INTERRUPT, tval: '0};
    end else if (_csr_status.mie.ssip && _mie_pending_ssip &&
                 (_csr_status.mideleg[1] ? _supervisor_interrupts_en :
                                          _machine_interrupts_en)) begin
      _interrupt_trap_req = '{
          valid: 1'b1,
          src: TRAP_SRC_SUPERVISOR_SOFTWARE_INTERRUPT,
          tval: '0
      };
    end
  end

  always_comb begin
    _id_trap_req = _if_id.trap_req.valid ? _if_id.trap_req : _ctrl.trap;
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
    .time_value(time_value),
    .retire(_mem_wb.valid && (_pipe_ctrl.mem_wb != STAGE_HOLD) && !_mem_wb.trap.valid),
    .csr_read_data(_csr.read_data),
    .illegal_csr(_csr.illegal),
    .status(_csr_status)
  );

  csr_access_control _csr_access_control (
    .csr_en(_csr.en),
    .csr_write_en(_csr.write_en),
    .csr_addr(_csr.addr),
    .priv_mode(_csr_status.priv_mode),
    .mcounteren(_csr_status.mcounteren),
    .scounteren(_csr_status.scounteren),
    .illegal_csr_access(_csr_access_illegal)
  );

  system_access_control _system_access_control (
    .system_ctrl(_id_ex.ctrl.system),
    .priv_mode(_csr_status.priv_mode),
    .tsr(_csr_status.mstatus.tsr),
    .tvm(_csr_status.mstatus.tvm),
    .illegal_system_access(_system_access_illegal)
  );

  // Pipeline control
  redirect_control _redirect_control (
    .id_ex_valid(_id_ex.valid),
    .id_ex_pc_src(_ex_pc_src),
    .id_ex_clear_pc_lsb(_id_ex.ctrl.clear_pc_lsb),
    .alu_result(_alu_result),
    .redirect(_execute_redirect),
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
    .trap_in_flight(_trap_in_flight),
    .trap_from_id(_trap_from_id)
  );

  flow_control _flow_control (
    .redirect(_execute_redirect),
    .mem_order_redirect(_mem_order_redirect),
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
    .mem_order_start(_mem_order_start),
    .mem_order_busy(_mem_order_busy),
    .execute_wait(_execute_wait),
    .pipe_ctrl(_pipe_ctrl)
  );

  // Fetch
  mem_arbiter _mem_arbiter (
    .clk(clk),
    .rst(rst),
    .ifetch(_ifetch_cache_arb.slave),
    .data(_data_cache_arb.slave),
    .mem(_physical_mem.master)
  );

  physical_memory_port _physical_memory_port (
    .clk(clk),
    .rst(rst),
    .upstream(_physical_mem.slave),
    .downstream(mem)
  );

  mem_arbiter _ifetch_translation_arbiter (
    .clk(clk),
    .rst(rst),
    .ifetch(_ifetch_walker_arb.slave),
    .data(_ifetch_adapter_arb.slave),
    .mem(_ifetch_ifu_cache.master)
  );

  translation_adapter _ifetch_translation_adapter (
    .clk(clk),
    .rst(rst),
    .ctx(_ifetch_translation_ctx),
    .satp(_csr_status.satp),
    .upstream(_ifetch_ifu_adapter.slave),
    .translation(_ifetch_translation.requester),
    .downstream(_ifetch_adapter_arb.master)
  );

  sv32_walker _ifetch_walker (
    .clk(clk),
    .rst(rst),
    .satp(_csr_status.satp),
    .translation(_ifetch_translation.responder),
    .memory(_ifetch_walker_arb.master)
  );

  l1_cache #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _l1i_cache (
    .clk(clk),
    .rst(rst),
    .upstream(_ifetch_ifu_cache.slave),
    .downstream(_ifetch_cache_arb.master),
    .cache_command(_icache_command)
  );

  ifu _ifu (
    .clk(clk),
    .rst(rst),
    .fetch_en(_pipe_ctrl.fetch == STAGE_ADVANCE),
    .redirect(_flow.redirect),
    .pc(pc),
    .fetched(_fetched),
    .ibus(_ifetch_ifu_adapter.master)
  );

  // Decode
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
  integer_execute _integer_execute (
    .clk(clk),
    .rst(rst),
    .valid(_id_ex.valid),
    .cancel(_pipe_ctrl.id_ex == STAGE_FLUSH),
    .result_ready(_pipe_ctrl.id_ex == STAGE_ADVANCE),
    .ctrl(_id_ex.ctrl),
    .branch_funct3(_id_ex.slot.instr.r.funct3.br),
    .pc(_id_ex.slot.pc),
    .rs1_data(_ex_rs1_operand),
    .rs2_data(_ex_rs2_operand),
    .imm(_id_ex.imm),
    .alu_result(_alu_result),
    .store_data(_store_data),
    .pc_src(_ex_pc_src),
    .execute_wait(_execute_wait)
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
  mem_order_control _mem_order_control (
    .clk(clk),
    .rst(rst),
    .ex_mem(_ex_mem),
    .dbus_wait(_dbus_wait),
    .trap_in_flight(_trap_in_flight),
    .start(_mem_order_start),
    .busy(_mem_order_busy),
    .redirect(_mem_order_redirect),
    .dcache_command(_dcache_command),
    .icache_command(_icache_command)
  );

  l1_cache #(
    .CacheableBase(CacheableBase),
    .CacheableEnd (CacheableEnd)
  ) _l1d_cache (
    .clk(clk),
    .rst(rst),
    .upstream(_data_lsu_cache.slave),
    .downstream(_data_cache_arb.master),
    .cache_command(_dcache_command)
  );

  mem_arbiter _data_translation_arbiter (
    .clk(clk),
    .rst(rst),
    .ifetch(_data_walker_arb.slave),
    .data(_data_adapter_arb.slave),
    .mem(_data_lsu_cache.master)
  );

  translation_adapter _data_translation_adapter (
    .clk(clk),
    .rst(rst),
    .ctx(_data_translation_ctx),
    .satp(_csr_status.satp),
    .upstream(_data_lsu_adapter.slave),
    .translation(_data_translation.requester),
    .downstream(_data_adapter_arb.master)
  );

  sv32_walker _data_walker (
    .clk(clk),
    .rst(rst),
    .satp(_csr_status.satp),
    .translation(_data_translation.responder),
    .memory(_data_walker_arb.master)
  );

  mem_stage _mem_stage (
    .clk(clk),
    .rst(rst),
    .ex_mem(_ex_mem),
    .csr_status(_csr_status),
    .mem_wait(_dbus_wait),
    .mem_wb_payload(_mem_wb_payload),
    .dbus(_data_lsu_adapter.master)
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
      halted <= 1'b0;
      _if_id.valid <= 1'b0;
      _id_ex.valid <= 1'b0;
      _ex_mem.valid <= 1'b0;
      _mem_wb.valid <= 1'b0;
    end else begin
      unique case (_pipe_ctrl.if_id)
        STAGE_HOLD: begin
        end
        STAGE_FLUSH: _if_id.valid <= 1'b0;
        STAGE_ADVANCE: begin
          if (_fetched.valid) begin
            _if_id <= _fetched;
          end else begin
            _if_id.valid <= 1'b0;
          end
        end
      endcase

      unique case (_pipe_ctrl.id_ex)
        STAGE_HOLD: begin
        end
        STAGE_FLUSH: _id_ex.valid <= 1'b0;
        STAGE_ADVANCE: begin
          if (_if_id.valid) begin
            _id_ex <= '{
                valid: 1'b1,
                slot: _if_id.slot,
                ctrl: _ctrl,
                rs1_operand: _id_rs1_operand,
                rs2_operand: _id_rs2_operand,
                imm: _id_imm,
                trap: _id_trap
            };
          end else begin
            _id_ex.valid <= 1'b0;
          end
        end
      endcase

      unique case (_pipe_ctrl.ex_mem)
        STAGE_HOLD: begin
        end
        STAGE_FLUSH: _ex_mem.valid <= 1'b0;
        STAGE_ADVANCE: begin
          if (_id_ex.valid) begin
            _ex_mem <= '{
                valid: 1'b1,
                pc: _id_ex.slot.pc,
                ctrl: _id_ex.ctrl,
                alu_result: _alu_result,
                execute_result: _ex_result,
                write_data: _store_data,
                rd: _id_ex.slot.instr.r.rd,
                trap: _ex_trap
            };
          end else begin
            _ex_mem.valid <= 1'b0;
          end
        end
      endcase

      unique case (_pipe_ctrl.mem_wb)
        STAGE_HOLD: begin
        end
        STAGE_FLUSH:   _mem_wb.valid <= 1'b0;
        STAGE_ADVANCE: _mem_wb <= _mem_wb_payload;
      endcase
    end
  end

endmodule
