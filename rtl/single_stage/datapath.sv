`timescale 1ns / 1ps

module datapath
  import riscv_pkg::*;
(
  input logic   clk,
  input instr_u instr,
  input pc_t    pc,

  input logic            reg_write,
  input imm_src_t        imm_src,
  input alu_src_t        alu_src,
  input alu_result_src_t alu_result_src,
  input alu_select_t     alu_select,
  input result_src_t     result_src,
  input logic            sub_arith,
  input logic            branch_sgnd,

  input word_t read_data,  // later from dmem/LSU

  output pc_t           ieu_addr,     // branch/jump target
  output word_t         alu_result,   // later dmem address
  output word_t         write_data,   // later store data
  output branch_flags_t branch_flags
);

  word_t rd_data1;
  word_t rd_data2;
  word_t wr_data;
  word_t imm_ext;
  word_t src_a;
  word_t src_b;
  word_t alu_result_mux;

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
      ALU_RES_ALU: alu_result_mux = alu_result;
      ALU_RES_PC_PLUS4: alu_result_mux = pc + pc_t'(4);
      ALU_RES_IMM: alu_result_mux = imm_ext;
    endcase

    unique case (result_src)
      RESULT_ALU: wr_data = alu_result_mux;
      RESULT_MEM: wr_data = read_data;
    endcase
  end

endmodule
