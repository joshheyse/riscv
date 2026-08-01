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

  logic            _clk;
  instr_u          _instr;
  pc_t             _pc;
  logic            _reg_write;
  imm_src_t        _imm_src;
  alu_src_t        _alu_src;
  alu_result_src_t _alu_result_src;
  alu_select_t     _alu_select;
  result_src_t     _result_src;
  logic            _sub_arith;
  logic            _branch_sgnd;
  word_t           _read_data;
  pc_t             _ieu_addr;
  word_t           _alu_result;
  word_t           _write_data;
  branch_flags_t   _branch_flags;

  int unsigned     errors = 0;
  int unsigned     checks = 0;
  int unsigned     printed = 0;

  datapath _dut (
    .clk(_clk),
    .instr(_instr),
    .pc(_pc),
    .reg_write(_reg_write),
    .imm_src(_imm_src),
    .alu_src(_alu_src),
    .alu_result_src(_alu_result_src),
    .alu_select(_alu_select),
    .result_src(_result_src),
    .sub_arith(_sub_arith),
    .branch_sgnd(_branch_sgnd),
    .read_data(_read_data),
    .ieu_addr(_ieu_addr),
    .alu_result(_alu_result),
    .write_data(_write_data),
    .branch_flags(_branch_flags)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
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
    @(posedge _clk);
    #1;
  endtask

  task automatic set_defaults;
    _instr.raw      = r_instr(7'b0000000, 5'd0, 5'd0, 3'b000, 5'd0, OP_R);
    _pc             = 32'h0000_0000;
    _reg_write      = 1'b0;
    _imm_src        = IMM_I;
    _alu_src        = ALU_SRC_RS1_RS2;
    _alu_result_src = ALU_RES_ALU;
    _alu_select     = ALU_ADDSUB;
    _result_src     = RESULT_ALU;
    _sub_arith      = 1'b0;
    _branch_sgnd    = 1'b1;
    _read_data      = 32'h0000_0000;
  endtask

  task automatic write_lui(input regaddr_t rd, input logic [19:0] imm20, input string what);
    @(negedge _clk);
    _instr.raw      = u_instr(imm20, rd, OP_LUI);
    _reg_write      = 1'b1;
    _imm_src        = IMM_U;
    _alu_src        = ALU_SRC_RS1_RS2;
    _alu_result_src = ALU_RES_IMM;
    _result_src     = RESULT_ALU;
    commit();
    _reg_write = 1'b0;
    $display("tb_datapath: wrote %s", what);
  endtask

  task automatic write_mem(input regaddr_t rd, input word_t data, input string what);
    @(negedge _clk);
    _instr.raw      = i_instr(12'h000, 5'd0, 3'b010, rd, OP_LOAD);
    _read_data      = data;
    _reg_write      = 1'b1;
    _imm_src        = IMM_I;
    _alu_result_src = ALU_RES_ALU;
    _result_src     = RESULT_MEM;
    commit();
    _reg_write = 1'b0;
    $display("tb_datapath: wrote %s", what);
  endtask

  // ---------------------------------------------------------------- tests --

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_datapath);
    end

    set_defaults();
    @(negedge _clk);

    // Seed a few registers through the datapath writeback muxes.
    write_lui(5'd1, 20'h12345, "x1 = 0x12345000 via LUI/immediate writeback");
    write_mem(5'd2, 32'h0000_0010, "x2 = 0x00000010 via memory writeback");

    // R-type ALU path: x1 + x2.
    @(negedge _clk);
    _instr.raw      = r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OP_R);
    _reg_write      = 1'b1;
    _alu_src        = ALU_SRC_RS1_RS2;
    _alu_select     = ALU_ADDSUB;
    _sub_arith      = 1'b0;
    _alu_result_src = ALU_RES_ALU;
    _result_src     = RESULT_ALU;
    settle();
    expect_word(_alu_result, 32'h1234_5010, "R-type add ALU result");
    expect_word(_ieu_addr, 32'h1234_5010, "IEU address follows ALU result");
    commit();

    // Read x3 back by using it as rs1 in an add-immediate operation.
    @(negedge _clk);
    _reg_write = 1'b0;
    _instr.raw = i_instr(12'h001, 5'd3, 3'b000, 5'd0, OP_I_ALU);
    _imm_src   = IMM_I;
    _alu_src   = ALU_SRC_RS1_IMM;
    settle();
    expect_word(_alu_result, 32'h1234_5011, "x3 writeback visible on rs1");

    // Store data comes directly from rs2.
    _instr.raw = r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd0, OP_STORE);
    settle();
    expect_word(_write_data, 32'h0000_0010, "store write_data is rs2 value");

    // PC + immediate target path.
    _pc        = 32'h0000_0100;
    _instr.raw = b_instr(13'd16, 5'd2, 5'd1, 3'b000);
    _imm_src   = IMM_B;
    _alu_src   = ALU_SRC_PC_IMM;
    settle();
    expect_word(_alu_result, 32'h0000_0110, "PC+imm branch target");
    expect_word(_ieu_addr, 32'h0000_0110, "IEU address carries branch target");

    // PC+4 link writeback path for jal/jalr-style instructions.
    @(negedge _clk);
    _pc             = 32'h0000_0200;
    _instr.raw      = i_instr(12'h004, 5'd1, 3'b000, 5'd4, OP_JALR);
    _imm_src        = IMM_I;
    _alu_src        = ALU_SRC_RS1_IMM;
    _alu_result_src = ALU_RES_PC_PLUS4;
    _result_src     = RESULT_ALU;
    _reg_write      = 1'b1;
    commit();

    @(negedge _clk);
    _reg_write      = 1'b0;
    _instr.raw      = i_instr(12'h000, 5'd4, 3'b000, 5'd0, OP_I_ALU);
    _imm_src        = IMM_I;
    _alu_src        = ALU_SRC_RS1_IMM;
    _alu_result_src = ALU_RES_ALU;
    _result_src     = RESULT_ALU;
    settle();
    expect_word(_alu_result, 32'h0000_0204, "PC+4 writeback visible in x4");

    // Comparator signedness reaches branch_flags.lt.
    write_mem(5'd6, 32'hffff_ffff, "x6 = -1/unsigned max");
    write_mem(5'd7, 32'h0000_0001, "x7 = 1");

    @(negedge _clk);
    _reg_write   = 1'b0;
    _instr.raw   = r_instr(7'b0000000, 5'd7, 5'd6, 3'b000, 5'd0, OP_BRANCH);
    _branch_sgnd = 1'b1;
    settle();
    expect_bit(_branch_flags.eq, 1'b0, "comparator eq for -1 vs 1");
    expect_bit(_branch_flags.lt, 1'b1, "signed comparator sees -1 < 1");

    _branch_sgnd = 1'b0;
    settle();
    expect_bit(_branch_flags.lt, 1'b0, "unsigned comparator sees max > 1");

    if (errors == 0) begin
      $display("tb_datapath: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_datapath: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_datapath: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
