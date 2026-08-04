`timescale 1ns / 1ps

module forwarding_unit
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input  id_ex_t    id_ex,
  input  ex_mem_t   ex_mem,
  input  mem_wb_t   mem_wb,
  output reg_data_t rs1_operand,
  output reg_data_t rs2_operand
);

  logic _ex_mem_can_forward;
  logic _mem_wb_can_forward;

  always_comb begin
    rs1_operand = id_ex.rs1_operand;
    rs2_operand = id_ex.rs2_operand;

    _ex_mem_can_forward = ex_mem.valid && ex_mem.ctrl.reg_write_en && (ex_mem.rd != 5'd0) && (ex_mem.ctrl.writeback_result != WB_RESULT_MEM);
    _mem_wb_can_forward = writes_rd(mem_wb.valid, mem_wb.ctrl.reg_write_en, mem_wb.rd);

    if (_ex_mem_can_forward && (ex_mem.rd == id_ex.instr.r.rs1)) begin
      rs1_operand = ex_mem.execute_result;
    end else if (_mem_wb_can_forward && (mem_wb.rd == id_ex.instr.r.rs1)) begin
      rs1_operand = mem_wb.result;
    end

    if (_ex_mem_can_forward && (ex_mem.rd == id_ex.instr.r.rs2)) begin
      rs2_operand = ex_mem.execute_result;
    end else if (_mem_wb_can_forward && (mem_wb.rd == id_ex.instr.r.rs2)) begin
      rs2_operand = mem_wb.result;
    end

  end

  logic _unused_id_ex;
  assign _unused_id_ex = |{id_ex.valid, id_ex.pc, id_ex.ctrl, id_ex.imm, id_ex.rd, id_ex.trap};

  logic _unused_ex_mem;
  assign _unused_ex_mem = |{ex_mem.pc, ex_mem.ctrl, ex_mem.alu_result, ex_mem.write_data, ex_mem.trap};

  logic _unused_mem_wb;
  assign _unused_mem_wb = |{mem_wb.trap};

endmodule
