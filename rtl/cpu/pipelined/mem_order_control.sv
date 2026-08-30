`timescale 1ns / 1ps

module mem_order_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic    clk,
  input logic    rst,
  /* verilator lint_off UNUSEDSIGNAL */
  input ex_mem_t ex_mem,
  /* verilator lint_on UNUSEDSIGNAL */
  input logic    dbus_wait,
  input logic    trap_in_flight,

  output logic           busy,
  output logic           start,
  output redirect_t      redirect,
  output tlb_flush_req_t tlb_flush,

  cache_command_if.requester dcache_command,
  cache_command_if.requester icache_command
);

  typedef enum logic [2:0] {
    IDLE,
    D_REQUEST,
    D_WAIT,
    I_REQUEST,
    I_WAIT,
    COMPLETE
  } state_e;

  state_e         _state;
  logic           _maintenance_instruction;
  logic           _maintenance_request;
  logic           _sfence_vma;
  pc_t            _fence_pc;
  tlb_flush_req_t _sfence_tlb_flush;

  assign _maintenance_instruction = ex_mem.valid
    && ((ex_mem.ctrl.mem_order == MEM_ORDER_FENCE_I)
        || (ex_mem.ctrl.mem_order == MEM_ORDER_SFENCE_VMA))
    && !ex_mem.trap.valid
    && !trap_in_flight;
  assign _maintenance_request = _maintenance_instruction && !dbus_wait;

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= IDLE;
      _sfence_vma <= 1'b0;
      _sfence_tlb_flush <= '0;
    end else begin
      unique case (_state)
        IDLE: begin
          if (_maintenance_instruction) begin
            _fence_pc <= ex_mem.pc;
            _sfence_vma <= ex_mem.ctrl.mem_order == MEM_ORDER_SFENCE_VMA;
            _sfence_tlb_flush <= ex_mem.tlb_flush;
          end
          if (_maintenance_request) begin
            _state <= D_REQUEST;
          end
        end
        D_REQUEST: begin
          if (dcache_command.valid && dcache_command.ready) begin
            _state <= D_WAIT;
          end
        end
        D_WAIT: begin
          if (dcache_command.done_valid && dcache_command.done_ready) begin
            _state <= I_REQUEST;
          end
        end
        I_REQUEST: begin
          if (icache_command.valid && icache_command.ready) begin
            _state <= I_WAIT;
          end
        end
        I_WAIT: begin
          if (icache_command.done_valid && icache_command.done_ready) begin
            _state <= COMPLETE;
          end
        end
        COMPLETE: begin
          _state <= IDLE;
        end
      endcase
    end
  end

  always_comb begin
    start = '0;
    busy = '0;
    redirect = '0;
    tlb_flush = '0;
    dcache_command.valid = '0;
    dcache_command.done_ready = '0;
    dcache_command.op = '0;
    icache_command.valid = '0;
    icache_command.done_ready = '0;
    icache_command.op = '0;
    case (_state)
      IDLE: begin
        if (_maintenance_request) begin
          start = 1'b1;
        end
      end
      D_REQUEST: begin
        dcache_command.valid = 1'b1;
        dcache_command.op.clean = 1'b1;
        dcache_command.op.invalidate = 1'b0;
        busy = 1'b1;
      end
      D_WAIT: begin
        dcache_command.done_ready = 1'b1;
        busy = 1'b1;
      end
      I_REQUEST: begin
        icache_command.valid = 1'b1;
        icache_command.op.clean = 1'b0;
        icache_command.op.invalidate = 1'b1;
        busy = 1'b1;
      end
      I_WAIT: begin
        icache_command.done_ready = 1'b1;
        busy = 1'b1;
      end
      COMPLETE: begin
        redirect.valid = 1'b1;
        redirect.pc = _fence_pc + pc_t'(4);
        if (_sfence_vma) begin
          tlb_flush = _sfence_tlb_flush;
          tlb_flush.valid = 1'b1;
        end
      end
      default: begin
      end
    endcase
  end

endmodule
