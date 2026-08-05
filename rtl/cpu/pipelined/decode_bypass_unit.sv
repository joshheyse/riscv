`timescale 1ns / 1ps

module decode_bypass_unit
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  /* verilator lint_off UNUSEDSIGNAL */
  input  if_id_t    if_id,
  input  mem_wb_t   mem_wb,
  /* verilator lint_on UNUSEDSIGNAL */
  input  reg_data_t rf_rs1_read,
  input  reg_data_t rf_rs2_read,
  output reg_data_t id_rs1_operand,
  output reg_data_t id_rs2_operand
);

  logic _mem_wb_can_bypass;

  always_comb begin
    _mem_wb_can_bypass = writes_rd(mem_wb.valid, mem_wb.ctrl.reg_write_en, mem_wb.rd);

    id_rs1_operand = rf_rs1_read;
    id_rs2_operand = rf_rs2_read;

    if (_mem_wb_can_bypass && (mem_wb.rd == if_id.instr.r.rs1)) begin
      id_rs1_operand = mem_wb.result;
    end

    if (_mem_wb_can_bypass && (mem_wb.rd == if_id.instr.r.rs2)) begin
      id_rs2_operand = mem_wb.result;
    end
  end

endmodule
