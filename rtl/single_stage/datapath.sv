`timescale 1ns / 1ps

// Single-cycle execution datapath.
//
// This module contains the register file, immediate extender, ALU operand
// muxes, ALU, branch comparator, store-data path, and writeback muxes. The
// controller supplies only selectors and enables; instruction field extraction
// happens here where the register/immediate datapath uses those fields.
//
// ALU operand mux:
//   alu_src           src_a      src_b
//   ----------------  ---------  --------
//   riscv_pkg::ALU_SRC_RS1_RS2   rd_data1   rd_data2
//   riscv_pkg::ALU_SRC_RS1_IMM   rd_data1   imm_ext
//   riscv_pkg::ALU_SRC_PC_IMM    pc         imm_ext
//
// Writeback mux:
//   alu_result_src     pre-memory value
//   -----------------  ----------------
//   riscv_pkg::ALU_RES_ALU        alu_result
//   riscv_pkg::ALU_RES_PC_PLUS4   pc + 4
//   riscv_pkg::ALU_RES_IMM        imm_ext
//
//   result_src         regfile wr_data
//   ----------         ----------------
//   riscv_pkg::RESULT_ALU         pre-memory value
//   riscv_pkg::RESULT_MEM         read_data from LSU
//
module datapath (
  input logic   clk,
  input riscv_pkg::instr_u instr,
  input riscv_pkg::pc_t    pc,

  input logic                       reg_write,
  input riscv_pkg::imm_src_t        imm_src,
  input riscv_pkg::alu_src_t        alu_src,
  input riscv_pkg::alu_result_src_t alu_result_src,
  input riscv_pkg::alu_select_t     alu_select,
  input riscv_pkg::result_src_t     result_src,
  input logic                       sub_arith,
  input logic                       branch_sgnd,

  input riscv_pkg::word_t read_data,  // later from dmem/LSU

  output riscv_pkg::pc_t           ieu_addr,     // branch/jump target
  output riscv_pkg::word_t         alu_result,   // later dmem address
  output riscv_pkg::word_t         write_data,   // later store data
  output riscv_pkg::branch_flags_t branch_flags
);

  riscv_pkg::word_t rd_data1;
  riscv_pkg::word_t rd_data2;
  riscv_pkg::word_t wr_data;
  riscv_pkg::word_t imm_ext;
  riscv_pkg::word_t src_a;
  riscv_pkg::word_t src_b;
  riscv_pkg::word_t alu_result_mux;

  extend ext (
    .imm_src(imm_src),
    .instr  (instr[31:7]),
    .imm_ext(imm_ext)
  );

  reg_file regfile (
    .clk(clk),
    .rd_addr1(instr.r.rs1),
    .rd_addr2(instr.r.rs2),
    .wr_addr(instr.r.rd),
    .wr_data(wr_data),
    .wr_en(reg_write),
    .rd_data1(rd_data1),
    .rd_data2(rd_data2)
  );

  comparator c (
    .src_a(rd_data1),
    .src_b(rd_data2),
    .sngd(branch_sgnd),
    .eq(branch_flags.eq),
    .lt(branch_flags.lt)
  );

  assign src_a = alu_src[1] ? pc : rd_data1;
  assign src_b = alu_src[0] ? imm_ext : rd_data2;
  assign write_data = rd_data2;
  assign ieu_addr = alu_result;

  alu al (
    .src_a(src_a),
    .src_b(src_b),
    .alu_select(alu_select),
    .sub_arith(sub_arith),
    .alu_result(alu_result)
  );

  always_comb begin
    unique case (alu_result_src)
      riscv_pkg::ALU_RES_ALU: alu_result_mux = alu_result;
      riscv_pkg::ALU_RES_PC_PLUS4: alu_result_mux = pc + riscv_pkg::pc_t'(4);
      riscv_pkg::ALU_RES_IMM: alu_result_mux = imm_ext;
    endcase

    unique case (result_src)
      riscv_pkg::RESULT_ALU: wr_data = alu_result_mux;
      riscv_pkg::RESULT_MEM: wr_data = read_data;
    endcase
  end

endmodule
