// tb_datapath.sv — self-checking testbench for the single-cycle datapath.
//
//   make sim  TB=datapath
//   make wave TB=datapath
//
// Drives controller outputs directly and checks the datapath wiring around the
// register file, extender, ALU, comparator, store data, IEU address, and
// writeback muxes.

`timescale 1ns / 1ps

module tb_datapath
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;
  localparam int unsigned MaxPrintedFailures = 24;

  logic            clk;
  instr_u          instr;
  pc_t             pc;
  logic            reg_write;
  imm_src_t        imm_src;
  alu_src_t        alu_src;
  alu_result_src_t alu_result_src;
  alu_select_t     alu_select;
  result_src_t     result_src;
  logic            sub_arith;
  logic            branch_sgnd;
  word_t           read_data;
  pc_t             ieu_addr;
  word_t           alu_result;
  word_t           write_data;
  branch_flags_t   branch_flags;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  int unsigned     printed = 0;

  datapath dut (
    .clk(clk),
    .instr(instr),
    .pc(pc),
    .reg_write(reg_write),
    .imm_src(imm_src),
    .alu_src(alu_src),
    .alu_result_src(alu_result_src),
    .alu_select(alu_select),
    .result_src(result_src),
    .sub_arith(sub_arith),
    .branch_sgnd(branch_sgnd),
    .read_data(read_data),
    .ieu_addr(ieu_addr),
    .alu_result(alu_result),
    .write_data(write_data),
    .branch_flags(branch_flags)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // ------------------------------------------------------------- helpers --

  function automatic instr_t r_instr(input logic [6:0] funct7, input regaddr_t rs2,
                                     input regaddr_t rs1, input funct3_t funct3, input regaddr_t rd,
                                     input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic instr_t i_instr(input logic [11:0] imm, input regaddr_t rs1,
                                     input funct3_t funct3, input regaddr_t rd,
                                     input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic instr_t u_instr(input logic [19:0] imm20, input regaddr_t rd,
                                     input logic [6:0] opcode);
    return {imm20, rd, opcode};
  endfunction

  function automatic instr_t b_instr(input logic [12:0] imm, input regaddr_t rs2,
                                     input regaddr_t rs1, input funct3_t funct3);
    if (imm[0]) return 'x;
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], OP_BRANCH};
  endfunction

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL [%0t] %-42s got=0x%08h expected=0x%08h", $time, what, got, exp);
      end else if (printed == MaxPrintedFailures) begin
        printed++;
        $display("  ... further failures suppressed; see the summary for exact counts");
      end
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      if (printed < MaxPrintedFailures) begin
        printed++;
        $display("  FAIL [%0t] %-42s got=%b expected=%b", $time, what, got, exp);
      end
    end
  endtask

  task automatic settle;
    #1;
  endtask

  task automatic commit;
    @(posedge clk);
    #1;
  endtask

  task automatic set_defaults;
    instr.raw      = r_instr(7'b0000000, 5'd0, 5'd0, 3'b000, 5'd0, OP_R);
    pc             = 32'h0000_0000;
    reg_write      = 1'b0;
    imm_src        = IMM_I;
    alu_src        = ALU_SRC_RS1_RS2;
    alu_result_src = ALU_RES_ALU;
    alu_select     = ALU_ADDSUB;
    result_src     = RESULT_ALU;
    sub_arith      = 1'b0;
    branch_sgnd    = 1'b1;
    read_data      = 32'h0000_0000;
  endtask

  task automatic write_lui(input regaddr_t rd, input logic [19:0] imm20, input string what);
    @(negedge clk);
    instr.raw      = u_instr(imm20, rd, OP_LUI);
    reg_write      = 1'b1;
    imm_src        = IMM_U;
    alu_src        = ALU_SRC_RS1_RS2;
    alu_result_src = ALU_RES_IMM;
    result_src     = RESULT_ALU;
    commit();
    reg_write = 1'b0;
    $display("tb_datapath: wrote %s", what);
  endtask

  task automatic write_mem(input regaddr_t rd, input word_t data, input string what);
    @(negedge clk);
    instr.raw      = i_instr(12'h000, 5'd0, 3'b010, rd, OP_LOAD);
    read_data      = data;
    reg_write      = 1'b1;
    imm_src        = IMM_I;
    alu_result_src = ALU_RES_ALU;
    result_src     = RESULT_MEM;
    commit();
    reg_write = 1'b0;
    $display("tb_datapath: wrote %s", what);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_datapath);
    end

    set_defaults();
    @(negedge clk);

    // Seed a few registers through the datapath writeback muxes.
    write_lui(5'd1, 20'h12345, "x1 = 0x12345000 via LUI/immediate writeback");
    write_mem(5'd2, 32'h0000_0010, "x2 = 0x00000010 via memory writeback");

    // R-type ALU path: x1 + x2.
    @(negedge clk);
    instr.raw      = r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OP_R);
    reg_write      = 1'b1;
    alu_src        = ALU_SRC_RS1_RS2;
    alu_select     = ALU_ADDSUB;
    sub_arith      = 1'b0;
    alu_result_src = ALU_RES_ALU;
    result_src     = RESULT_ALU;
    settle();
    expect_word(alu_result, 32'h1234_5010, "R-type add ALU result");
    expect_word(ieu_addr, 32'h1234_5010, "IEU address follows ALU result");
    commit();

    // Read x3 back by using it as rs1 in an add-immediate operation.
    @(negedge clk);
    reg_write = 1'b0;
    instr.raw = i_instr(12'h001, 5'd3, 3'b000, 5'd0, OP_I_ALU);
    imm_src   = IMM_I;
    alu_src   = ALU_SRC_RS1_IMM;
    settle();
    expect_word(alu_result, 32'h1234_5011, "x3 writeback visible on rs1");

    // Store data comes directly from rs2.
    instr.raw = r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd0, OP_STORE);
    settle();
    expect_word(write_data, 32'h0000_0010, "store write_data is rs2 value");

    // PC + immediate target path.
    pc        = 32'h0000_0100;
    instr.raw = b_instr(13'd16, 5'd2, 5'd1, 3'b000);
    imm_src   = IMM_B;
    alu_src   = ALU_SRC_PC_IMM;
    settle();
    expect_word(alu_result, 32'h0000_0110, "PC+imm branch target");
    expect_word(ieu_addr, 32'h0000_0110, "IEU address carries branch target");

    // PC+4 link writeback path for jal/jalr-style instructions.
    @(negedge clk);
    pc             = 32'h0000_0200;
    instr.raw      = i_instr(12'h004, 5'd1, 3'b000, 5'd4, OP_JALR);
    imm_src        = IMM_I;
    alu_src        = ALU_SRC_RS1_IMM;
    alu_result_src = ALU_RES_PC_PLUS4;
    result_src     = RESULT_ALU;
    reg_write      = 1'b1;
    commit();

    @(negedge clk);
    reg_write      = 1'b0;
    instr.raw      = i_instr(12'h000, 5'd4, 3'b000, 5'd0, OP_I_ALU);
    imm_src        = IMM_I;
    alu_src        = ALU_SRC_RS1_IMM;
    alu_result_src = ALU_RES_ALU;
    result_src     = RESULT_ALU;
    settle();
    expect_word(alu_result, 32'h0000_0204, "PC+4 writeback visible in x4");

    // Comparator signedness reaches branch_flags.lt.
    write_mem(5'd6, 32'hffff_ffff, "x6 = -1/unsigned max");
    write_mem(5'd7, 32'h0000_0001, "x7 = 1");

    @(negedge clk);
    reg_write   = 1'b0;
    instr.raw   = r_instr(7'b0000000, 5'd7, 5'd6, 3'b000, 5'd0, OP_BRANCH);
    branch_sgnd = 1'b1;
    settle();
    expect_bit(branch_flags.eq, 1'b0, "comparator eq for -1 vs 1");
    expect_bit(branch_flags.lt, 1'b1, "signed comparator sees -1 < 1");

    branch_sgnd = 1'b0;
    settle();
    expect_bit(branch_flags.lt, 1'b0, "unsigned comparator sees max > 1");

    if (errors == 0) begin
      $display("tb_datapath: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_datapath: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge clk);
    $display("tb_datapath: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
