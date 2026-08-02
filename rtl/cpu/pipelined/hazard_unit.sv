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
(
  input logic        if_id_valid,
  input instr_u      if_id_instr,
  input logic        id_ex_valid,
  input logic        id_ex_reg_write_en,
  input regaddr_t    id_ex_rd,
  input logic        ex_mem_valid,
  input logic        ex_mem_reg_write_en,
  input regaddr_t    ex_mem_rd,
  input result_src_t ex_mem_result_src,

  output logic stall
);

  logic [4:0] rs1_addr;
  logic [4:0] rs2_addr;
  logic       uses_rs1;
  logic       uses_rs2;

  logic       _ex_mem_can_stall;

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

    _ex_mem_can_stall = ex_mem_valid && ex_mem_reg_write_en && (ex_mem_rd != 5'd0) && (ex_mem_result_src == RESULT_MEM);

    if (if_id_valid && uses_rs1) begin
      if (id_ex_valid && id_ex_reg_write_en && (id_ex_rd != '0) && (id_ex_rd == rs1_addr)) begin
        stall = 1'b1;
      end

      if (_ex_mem_can_stall && (ex_mem_rd == rs1_addr)) begin
        stall = 1'b1;
      end

    end

    if (if_id_valid && uses_rs2) begin
      if (id_ex_valid && id_ex_reg_write_en && (id_ex_rd != '0) && (id_ex_rd == rs2_addr)) begin
        stall = 1'b1;
      end

      if (_ex_mem_can_stall && (ex_mem_rd == rs2_addr)) begin
        stall = 1'b1;
      end

    end
  end

endmodule
