`timescale 1ns / 1ps

// Forwarding-aware decode-stage data hazard detector.
//
// The unit looks at the instruction currently held in IF/ID and compares its
// real source registers against the destination registers of older in-flight
// instructions. A match requests a stall so decode does not read stale register
// file data.
//
// ALU and writeback results are forwarded into execute, so most older producer
// matches do not need a stall. The remaining stalls are:
// - ID/EX producer: the value has not reached a forwarding source yet.
// - EX/MEM load producer: the memory value is not available from EX/MEM.
//
// x0 is ignored because writes to x0 are architecturally invisible.
//
module hazard_unit
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  /* verilator lint_off UNUSEDSIGNAL */
  input if_id_t  if_id,
  input id_ex_t  id_ex,
  input ex_mem_t ex_mem,
  /* verilator lint_on UNUSEDSIGNAL */

  output logic stall
);

  logic [4:0] _rs1_addr;
  logic [4:0] _rs2_addr;
  logic       _uses_rs1;
  logic       _uses_rs2;

  logic       _ex_mem_can_stall;

  always_comb begin
    stall = 1'b0;

    _uses_rs1 = 1'b0;
    _uses_rs2 = 1'b0;

    _rs1_addr = if_id.instr.r.rs1;
    _rs2_addr = if_id.instr.r.rs2;

    unique case (if_id.instr.r.opcode)
      OP_R: begin
        _uses_rs1 = 1'b1;
        _uses_rs2 = 1'b1;
      end

      OP_I_ALU, OP_LOAD, OP_JALR: begin
        _uses_rs1 = 1'b1;
      end

      OP_STORE, OP_BRANCH: begin
        _uses_rs1 = 1'b1;
        _uses_rs2 = 1'b1;
      end

      OP_JAL, OP_LUI, OP_AUIPC, OP_FENCE, OP_SYSTEM: begin
      end
    endcase

    _ex_mem_can_stall = writes_rd(ex_mem.valid, ex_mem.ctrl.reg_write_en, ex_mem.rd) && (ex_mem.ctrl.writeback_result == WB_RESULT_MEM);

    if (if_id.valid && _uses_rs1) begin
      if (writes_rd(id_ex.valid, id_ex.ctrl.reg_write_en, id_ex.rd) && (id_ex.rd == _rs1_addr)) begin
        stall = 1'b1;
      end

      if (_ex_mem_can_stall && (ex_mem.rd == _rs1_addr)) begin
        stall = 1'b1;
      end

    end

    if (if_id.valid && _uses_rs2) begin
      if (writes_rd(id_ex.valid, id_ex.ctrl.reg_write_en, id_ex.rd) && (id_ex.rd == _rs2_addr)) begin
        stall = 1'b1;
      end

      if (_ex_mem_can_stall && (ex_mem.rd == _rs2_addr)) begin
        stall = 1'b1;
      end

    end
  end

endmodule
