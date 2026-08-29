`timescale 1ns / 1ps

module mem_stage
  import riscv_pkg::*;
  import sv32_pkg::*;
  import pipelined_pkg::*;
(
  input logic clk,
  input logic rst,

  input ex_mem_t     ex_mem,
  input csr_status_t csr_status,

  input logic core_reservation_clear,

  output logic    mem_wait,
  output mem_wb_t mem_wb_payload,

  vmem_if.master dbus
);

  mem_data_t       _mem_read_data;
  reg_data_t       _normal_result_data;
  reg_data_t       _mem_result_data;
  logic            _normal_selected;
  logic            _normal_access;
  logic            _normal_wait;
  logic            _amo_selected;
  logic            _amo_access;
  logic            _memory_response_here;
  trap_req_t       _addr_trap_req;
  trap_req_t       _mmu_trap_req;
  trap_req_t       _mem_trap_req;
  trap_stage_t     _mem_trap;
  trap_stage_t     _trap;

  logic            _normal_accepted;
  logic            _normal_accept;
  logic            _normal_response_here;
  vmem_req_t       _normal_req;
  logic            _normal_req_ready;
  mem_data_t       _normal_write_data;
  mem_write_mask_t _normal_write_mask;
  /* verilator lint_off UNUSEDSIGNAL */
  vmem_rsp_t       _normal_rsp;
  /* verilator lint_on UNUSEDSIGNAL */
  logic            _normal_rsp_ready;

  amo_req_t        _amo_req;
  /* verilator lint_off UNUSEDSIGNAL */
  logic            _amo_req_ready;
  /* verilator lint_on UNUSEDSIGNAL */
  amo_rsp_t        _amo_rsp;
  logic            _amo_rsp_ready;
  logic            _ordinary_store_event;
  logic            _amo_reservation_clear;

  vmem_if _amo_memory (
    .clk(clk),
    .rst(rst)
  );


  always_comb begin
    _amo_selected = ex_mem.valid && !ex_mem.trap.valid && ex_mem.ctrl.amo.en;
    _normal_selected = ex_mem.valid && !ex_mem.trap.valid && !_amo_selected &&
      (ex_mem.ctrl.mem_write_en || ex_mem.ctrl.writeback_result == WB_RESULT_MEM);
    _normal_access = _normal_selected && !_addr_trap_req.valid;
    _amo_access = _amo_selected && !_addr_trap_req.valid;

    _normal_req = '0;
    _normal_req.valid = _normal_access && !_normal_accepted;
    _normal_req.write_en = _normal_access && ex_mem.ctrl.mem_write_en;
    _normal_req.addr = ex_mem.alu_result;
    _normal_req.write_data = _normal_write_data;
    _normal_req.write_mask = _normal_write_mask;

    _normal_accept = _normal_req.valid && _normal_req_ready;
    _normal_response_here = _normal_rsp.valid && (_normal_accepted || _normal_accept);
    _normal_wait = _normal_access && !_normal_response_here;
    _memory_response_here = _amo_selected ? _amo_rsp.valid : _normal_response_here;
    mem_wait = _normal_wait || (_amo_access && !_amo_rsp.valid);
    _normal_rsp_ready = 1'b1;
    _amo_rsp_ready = _amo_selected;

    _amo_req = '{
        valid: _amo_access,
        ctrl: ex_mem.ctrl.amo,
        address: virtual_address_u'(ex_mem.alu_result),
        operand: ex_mem.write_data,
        ctx: '{
            access : ex_mem.ctrl.amo.op == AMO_OP_LR ? MMU_ACCESS_LOAD : MMU_ACCESS_STORE,
            privilege: effective_data_privilege(csr_status.priv_mode, csr_status.mstatus),
            sum: csr_status.mstatus.sum,
            mxr: csr_status.mstatus.mxr
        }
    };
  end

  always_comb begin
    // The ordinary load/store path owns dbus by default. An AMO takes all four
    // handshake signals for its complete read-modify-write transaction.
    dbus.req = _normal_req;
    _normal_req_ready = dbus.req_ready;
    _normal_rsp = dbus.rsp;
    dbus.rsp_ready = _normal_rsp_ready;
    _amo_memory.req_ready = 1'b0;
    _amo_memory.rsp = '0;
    _ordinary_store_event = '0;

    if (_amo_selected) begin
      dbus.req = _amo_memory.req;
      _amo_memory.req_ready = dbus.req_ready;
      _amo_memory.rsp = dbus.rsp;
      dbus.rsp_ready = _amo_memory.rsp_ready;
      _normal_req_ready = 1'b0;
      _normal_rsp = '0;
    end else begin
      _ordinary_store_event = (dbus.req.write_en && (dbus.req.valid || dbus.rsp.valid));
    end

    _amo_reservation_clear = _ordinary_store_event || core_reservation_clear;

  end

  always_comb begin
    _mem_trap_req = _addr_trap_req;
    if (!_mem_trap_req.valid && _memory_response_here) begin
      _mem_trap_req = _mmu_trap_req;
    end

    _trap = ex_mem.trap.valid ? ex_mem.trap : _mem_trap;
    _mem_result_data = _amo_selected ? _amo_rsp.result : _normal_result_data;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _normal_accepted <= 1'b0;
    end else if (_normal_response_here) begin
      _normal_accepted <= 1'b0;
    end else if (_normal_accept) begin
      _normal_accepted <= 1'b1;
    end
  end

  mem_trap_control _mem_trap_control (
    .valid(_normal_selected || _amo_selected),
    .addr(ex_mem.alu_result),
    .mem_size(ex_mem.ctrl.mem_size),
    .mem_write_en(_amo_selected ? ex_mem.ctrl.amo.op != AMO_OP_LR : ex_mem.ctrl.mem_write_en),
    .trap(_addr_trap_req)
  );

  mmu_trap_control _mmu_trap_control (
    .fault(_amo_selected ? _amo_rsp.fault : _normal_rsp.fault),
    .access(_amo_selected ?
            (ex_mem.ctrl.amo.op == AMO_OP_LR ? MMU_ACCESS_LOAD : MMU_ACCESS_STORE) :
            (ex_mem.ctrl.mem_write_en ? MMU_ACCESS_STORE : MMU_ACCESS_LOAD)),
    .virtual_addr(ex_mem.alu_result),
    .trap_req(_mmu_trap_req)
  );

  trap_control _trap_control (
    .trap_req(_mem_trap_req),
    .pc(ex_mem.pc),
    .csr_status(csr_status),
    .trap(_mem_trap)
  );

  lsu _lsu (
    .addr(ex_mem.alu_result),
    .write_data(ex_mem.write_data),
    .mem_size(ex_mem.ctrl.mem_size),
    .mem_unsigned(ex_mem.ctrl.mem_unsigned),
    .read_data(_mem_read_data),
    .mem_write_data(_normal_write_data),
    .mem_read_data(_normal_rsp.read_data),
    .write_mask(_normal_write_mask)
  );

  writeback_mux _mem_result_mux (
    .writeback_result(ex_mem.ctrl.writeback_result),
    .execute_result(ex_mem.execute_result),
    .read_data(_mem_read_data),
    .writeback_data(_normal_result_data)
  );

  amo_execute _amo_execute (
    .clk(clk),
    .rst(rst),
    .req(_amo_req),
    .req_ready(_amo_req_ready),
    .rsp(_amo_rsp),
    .rsp_ready(_amo_rsp_ready),
    .reservation_clear(_amo_reservation_clear),
    .memory(_amo_memory.master)
  );

  assign mem_wb_payload = '{
          valid: ex_mem.valid,
          ctrl: ex_mem.ctrl,
          result: _mem_result_data,
          rd: ex_mem.rd,
          trap: _trap
      };

  a_memory_sources_exclusive :
  assert property (@(posedge clk) disable iff (rst) !(_normal_req.valid && _amo_memory.req.valid))
  else $error("mem_stage: ordinary LSU and AMO requested dbus simultaneously");

  a_amo_blocks_normal_request :
  assert property (@(posedge clk) disable iff (rst) _amo_selected |-> !_normal_req.valid)
  else $error("mem_stage: younger ordinary memory request issued during AMO");

endmodule
