`timescale 1ns / 1ps

module hazard_unit
  import riscv_pkg::*;
  import pipelined_pkg::*;
(
  input logic     if_id_valid,
  input instr_u   if_id_instr,
  input logic     id_ex_valid,
  input logic     id_ex_reg_write_en,
  input regaddr_t id_ex_rd,
  input logic     ex_mem_valid,
  input logic     ex_mem_reg_write_en,
  input regaddr_t ex_mem_rd,
  input logic     mem_wb_valid,
  input logic     mem_wb_reg_write_en,
  input regaddr_t mem_wb_rd,

  output logic stall
);

  logic [4:0] rs1_addr;
  logic [4:0] rs2_addr;
  logic uses_rs1;
  logic uses_rs2;

  always_comb begin
    stall = 1'b0;

    uses_rs1 = 1'b0;
    uses_rs2 = 1'b0;

    rs1_addr = if_id_instr.r.rs1;
    rs2_addr = if_id_instr.r.rs2;

    unique case (if_id_instr.r.opcode)
      OP_R: begin
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
      end

      OP_I_ALU, OP_LOAD, OP_JALR: begin
        uses_rs1 = 1'b1;
      end

      OP_STORE, OP_BRANCH: begin
        uses_rs1 = 1'b1;
        uses_rs2 = 1'b1;
      end

      OP_JAL, OP_LUI, OP_AUIPC, OP_FENCE, OP_SYSTEM: begin
      end
    endcase

    if (if_id_valid && uses_rs1) begin
      if (id_ex_valid && id_ex_reg_write_en && (id_ex_rd != '0) && (id_ex_rd == rs1_addr)) begin
        stall = 1'b1;
      end

      if (ex_mem_valid && ex_mem_reg_write_en && (ex_mem_rd != '0) && (ex_mem_rd == rs1_addr)) begin
        stall = 1'b1;
      end

      if (mem_wb_valid && mem_wb_reg_write_en && (mem_wb_rd != '0) && (mem_wb_rd == rs1_addr)) begin
        stall = 1'b1;
      end
    end

    if (if_id_valid && uses_rs2) begin
      if (id_ex_valid && id_ex_reg_write_en && (id_ex_rd != '0) && (id_ex_rd == rs2_addr)) begin
        stall = 1'b1;
      end

      if (ex_mem_valid && ex_mem_reg_write_en && (ex_mem_rd != '0) && (ex_mem_rd == rs2_addr)) begin
        stall = 1'b1;
      end

      if (mem_wb_valid && mem_wb_reg_write_en && (mem_wb_rd != '0) && (mem_wb_rd == rs2_addr)) begin
        stall = 1'b1;
      end
    end
  end

endmodule
