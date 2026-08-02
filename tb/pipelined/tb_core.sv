// tb_core.sv - first bring-up checks for the pipelined core.
//
//   make sim DESIGN=pipelined TB=core
//   make wave DESIGN=pipelined TB=core
//
// This testbench grows one pipeline stage at a time as the implementation
// comes online.

`timescale 1ns / 1ps

module tb_core
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();

  int unsigned       errors = 0;
  int unsigned       checks = 0;

  pc_t               _pc_hold;
  pc_t               _if_id_pc_hold;
  instr_t            _if_id_instr_hold;
  logic              _if_id_valid_hold;
  pc_t               _id_ex_pc_hold;
  instr_t            _id_ex_instr_hold;
  logic              _id_ex_valid_hold;
  word_t             _ex_mem_alu_result_hold;
  regaddr_t          _ex_mem_rd_hold;
  logic              _ex_mem_valid_hold;
  word_t             _mem_wb_result_hold;
  regaddr_t          _mem_wb_rd_hold;
  logic              _mem_wb_valid_hold;
  word_t             _dbus_addr_hold;
  word_t             _dbus_write_data_hold;
  logic        [3:0] _dbus_write_mask_hold;

  logic              _unused_bus_bits;
  assign _unused_bus_bits = |{
    _ibus.rsp.ready,
    _ibus.rsp.instr.raw,
    _dbus.rsp.ready,
    _dbus.rsp.read_data,
    _dbus.req.write_en,
    _dbus.req.addr,
    _dbus.req.write_data,
    _dbus.req.write_mask
  };

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .ibus(_ibus),
    .dbus(_dbus)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_regaddr(input regaddr_t got, input regaddr_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got x%0d, expected x%0d", $time, what, got, exp);
    end
  endtask

  task automatic expect_addi_ctrl(input control_t got, input string what);
    checks++;
    if (got.reg_write_en !== 1'b1 ||
        got.mem_write_en !== 1'b0 ||
        got.imm_src !== IMM_I ||
        got.alu_src !== ALU_SRC_RS1_IMM ||
        got.alu_result_src !== ALU_RES_ALU ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== PC_SRC_INC ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_WORD ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b0 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected addi control bundle", $time, what);
    end
  endtask

  task automatic expect_auipc_ctrl(input control_t got, input string what);
    checks++;
    if (got.reg_write_en !== 1'b1 ||
        got.mem_write_en !== 1'b0 ||
        got.imm_src !== IMM_U ||
        got.alu_src !== ALU_SRC_PC_IMM ||
        got.alu_result_src !== ALU_RES_ALU ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== PC_SRC_INC ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_WORD ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b0 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected auipc control bundle", $time, what);
    end
  endtask

  task automatic expect_sh_ctrl(input control_t got, input string what);
    checks++;
    if (got.reg_write_en !== 1'b0 ||
        got.mem_write_en !== 1'b1 ||
        got.imm_src !== IMM_S ||
        got.alu_src !== ALU_SRC_RS1_IMM ||
        got.alu_result_src !== ALU_RES_ALU ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== PC_SRC_INC ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_HALF ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b0 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected sh control bundle", $time, what);
    end
  endtask

  task automatic expect_jal_ctrl(input control_t got, input string what);
    checks++;
    if (got.reg_write_en !== 1'b1 ||
        got.mem_write_en !== 1'b0 ||
        got.imm_src !== IMM_J ||
        got.alu_src !== ALU_SRC_PC_IMM ||
        got.alu_result_src !== ALU_RES_PC_PLUS4 ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== PC_SRC_IEU_ADR ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_WORD ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b0 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected jal control bundle", $time, what);
    end
  endtask

  task automatic expect_beq_ctrl(input control_t got, input pc_src_t exp_pc_src, input string what);
    checks++;
    if (got.reg_write_en !== 1'b0 ||
        got.mem_write_en !== 1'b0 ||
        got.imm_src !== IMM_B ||
        got.alu_src !== ALU_SRC_PC_IMM ||
        got.alu_result_src !== ALU_RES_ALU ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== exp_pc_src ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_WORD ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b0 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected beq control bundle", $time, what);
    end
  endtask

  task automatic expect_jalr_ctrl(input control_t got, input string what);
    checks++;
    if (got.reg_write_en !== 1'b1 ||
        got.mem_write_en !== 1'b0 ||
        got.imm_src !== IMM_I ||
        got.alu_src !== ALU_SRC_RS1_IMM ||
        got.alu_result_src !== ALU_RES_PC_PLUS4 ||
        got.alu_select !== ALU_ADDSUB ||
        got.result_src !== RESULT_ALU ||
        got.sub_arith !== 1'b0 ||
        got.pc_src !== PC_SRC_IEU_ADR ||
        got.branch_sgnd !== 1'b1 ||
        got.mem_size !== MEM_SIZE_WORD ||
        got.mem_unsigned !== 1'b0 ||
        got.clear_pc_lsb !== 1'b1 ||
        got.illegal_instr !== 1'b0) begin
      errors++;
      $display("  FAIL [%0t] %s: unexpected jalr control bundle", $time, what);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core);
    end

    _ibus.rsp = '0;
    _dbus.rsp = '0;
    _rst = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");
    expect_bit(_ibus.req.valid, 1'b0, "reset clears instruction request");
    expect_bit(_dbus.req.valid, 1'b0, "reset clears data request");

    @(negedge _clk);
    _rst = 1'b0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "fetch does not halt");
    expect_bit(_ibus.req.valid, 1'b1, "fetch requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "fetch starts at address zero");
    expect_bit(_dbus.req.valid, 1'b0, "fetch does not request data bus");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0050_0093;  // addi x1, x0, 5

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures first valid fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures first fetched pc");
    expect_word(_dut._fetched.instr.raw, 32'h0050_0093, "IFU captures first fetched instr");
    expect_word(_pc, 32'h0000_0004, "fetch accept advances pc");
    expect_word(_ibus.req.addr, 32'h0000_0004, "next fetch uses advanced pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0031_00b3;  // add x1, x2, x3

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures first valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID captures first fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h0050_0093, "IF/ID captures first fetched instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures second valid fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures second fetched pc");
    expect_word(_dut._fetched.instr.raw, 32'h0031_00b3, "IFU captures second fetched instr");
    expect_word(_pc, 32'h0000_0008, "second fetch advances pc");

    _dut._reg_file._regs[2] = 32'h1111_2222;
    _dut._reg_file._regs[3] = 32'h3333_4444;

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h1234_5297;  // auipc x5, 0x12345

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures second valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0004, "IF/ID captures second fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h0031_00b3, "IF/ID captures second fetched instr");
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures addi valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures addi pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0050_0093, "ID/EX captures addi instr");
    expect_addi_ctrl(_dut._id_ex.ctrl, "ID/EX captures addi control");
    expect_word(_dut._id_ex.rs1_data, 32'h0000_0000, "ID/EX addi rs1 data is zero");
    expect_word(_dut._id_ex.rs2_data, 32'h0000_0000, "ID/EX addi rs2 data is zero");
    expect_word(_dut._id_ex.imm, 32'h0000_0005, "ID/EX captures addi immediate");
    expect_word(_dut._src_a, 32'h0000_0000, "ADDI ALU src_a selects rs1");
    expect_word(_dut._src_b, 32'h0000_0005, "ADDI ALU src_b selects immediate");
    expect_word(_dut._alu_result, 32'h0000_0005, "ADDI ALU result");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures third valid fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0008, "IFU captures third fetched pc");
    expect_word(_dut._fetched.instr.raw, 32'h1234_5297, "IFU captures third fetched instr");
    expect_word(_pc, 32'h0000_000c, "third fetch advances pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0001_2303;  // lw x6, 0(x2)

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures third valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0008, "IF/ID captures third fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h1234_5297, "IF/ID captures third fetched instr");
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures second valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0004, "ID/EX captures second decoded pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0031_00b3, "ID/EX captures second decoded instr");
    expect_word(_dut._id_ex.rs1_data, 32'h1111_2222, "ID/EX captures rs1 data");
    expect_word(_dut._id_ex.rs2_data, 32'h3333_4444, "ID/EX captures rs2 data");
    expect_word(_dut._src_a, 32'h1111_2222, "ADD ALU src_a selects rs1");
    expect_word(_dut._src_b, 32'h3333_4444, "ADD ALU src_b selects rs2");
    expect_word(_dut._alu_result, 32'h4444_6666, "ADD ALU result");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures addi valid");
    expect_word(_dut._ex_mem.alu_result, 32'h0000_0005, "EX/MEM captures addi raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_0005, "EX/MEM captures addi execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd1, "EX/MEM captures addi rd");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures load valid fetch");
    expect_word(_dut._fetched.pc, 32'h0000_000c, "IFU captures load fetched pc");
    expect_word(_dut._fetched.instr.raw, 32'h0001_2303, "IFU captures load fetched instr");
    expect_word(_pc, 32'h0000_0010, "load fetch advances pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures load valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_000c, "IF/ID captures load fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h0001_2303, "IF/ID captures load fetched instr");
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures auipc valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0008, "ID/EX captures auipc pc");
    expect_word(_dut._id_ex.instr.raw, 32'h1234_5297, "ID/EX captures auipc instr");
    expect_auipc_ctrl(_dut._id_ex.ctrl, "ID/EX captures auipc control");
    expect_word(_dut._id_ex.imm, 32'h1234_5000, "ID/EX captures auipc immediate");
    expect_word(_dut._src_a, 32'h0000_0008, "AUIPC ALU src_a selects ID/EX pc");
    expect_word(_dut._src_b, 32'h1234_5000, "AUIPC ALU src_b selects ID/EX immediate");
    expect_word(_dut._alu_result, 32'h1234_5008, "AUIPC ALU result");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures add valid");
    expect_word(_dut._ex_mem.alu_result, 32'h4444_6666, "EX/MEM captures add raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h4444_6666, "EX/MEM captures add execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd1, "EX/MEM captures add rd");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures addi valid");
    expect_word(_dut._mem_wb.result, 32'h0000_0005, "MEM/WB captures addi result");
    expect_regaddr(_dut._mem_wb.rd, 5'd1, "MEM/WB captures addi rd");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[1], 32'h0000_0005, "WB writes addi result to x1");
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures load valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_000c, "ID/EX captures load pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0001_2303, "ID/EX captures load instr");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures auipc valid");
    expect_word(_dut._ex_mem.alu_result, 32'h1234_5008, "EX/MEM captures auipc raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h1234_5008, "EX/MEM captures auipc execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd5, "EX/MEM captures auipc rd");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures add valid");
    expect_word(_dut._mem_wb.result, 32'h4444_6666, "MEM/WB captures add result");
    expect_regaddr(_dut._mem_wb.rd, 5'd1, "MEM/WB captures add rd");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[1], 32'h4444_6666, "WB writes add result to x1");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures load valid");
    expect_word(_dut._ex_mem.alu_result, 32'h1111_2222, "EX/MEM captures load address");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures auipc valid");
    expect_word(_dut._mem_wb.result, 32'h1234_5008, "MEM/WB captures auipc result");
    expect_regaddr(_dut._mem_wb.rd, 5'd5, "MEM/WB captures auipc rd");
    expect_bit(_dbus.req.valid, 1'b1, "load requests data bus");
    expect_bit(_dbus.req.write_en, 1'b0, "load request is read");
    expect_word(_dbus.req.addr, 32'h1111_2222, "load request address");
    expect_bit(_dut._pipe_en, 1'b0, "load waits when data bus is not ready");
    expect_bit(_ibus.req.valid, 1'b0, "stall suppresses instruction request");

    _pc_hold                = _pc;
    _if_id_pc_hold          = _dut._if_id.pc;
    _if_id_instr_hold       = _dut._if_id.instr.raw;
    _if_id_valid_hold       = _dut._if_id.valid;
    _id_ex_pc_hold          = _dut._id_ex.pc;
    _id_ex_instr_hold       = _dut._id_ex.instr.raw;
    _id_ex_valid_hold       = _dut._id_ex.valid;
    _ex_mem_alu_result_hold = _dut._ex_mem.alu_result;
    _ex_mem_rd_hold         = _dut._ex_mem.rd;
    _ex_mem_valid_hold      = _dut._ex_mem.valid;
    _mem_wb_result_hold     = _dut._mem_wb.result;
    _mem_wb_rd_hold         = _dut._mem_wb.rd;
    _mem_wb_valid_hold      = _dut._mem_wb.valid;

    @(posedge _clk);
    #1;
    expect_word(_pc, _pc_hold, "stall holds pc");
    expect_word(_dut._if_id.pc, _if_id_pc_hold, "stall holds IF/ID pc");
    expect_word(_dut._if_id.instr.raw, _if_id_instr_hold, "stall holds IF/ID instr");
    expect_bit(_dut._if_id.valid, _if_id_valid_hold, "stall holds IF/ID valid");
    expect_word(_dut._id_ex.pc, _id_ex_pc_hold, "stall holds ID/EX pc");
    expect_word(_dut._id_ex.instr.raw, _id_ex_instr_hold, "stall holds ID/EX instr");
    expect_bit(_dut._id_ex.valid, _id_ex_valid_hold, "stall holds ID/EX valid");
    expect_word(_dut._ex_mem.alu_result, _ex_mem_alu_result_hold, "stall holds EX/MEM address");
    expect_regaddr(_dut._ex_mem.rd, _ex_mem_rd_hold, "stall holds EX/MEM rd");
    expect_bit(_dut._ex_mem.valid, _ex_mem_valid_hold, "stall holds EX/MEM valid");
    expect_word(_dut._mem_wb.result, _mem_wb_result_hold, "stall holds MEM/WB result");
    expect_regaddr(_dut._mem_wb.rd, _mem_wb_rd_hold, "stall holds MEM/WB rd");
    expect_bit(_dut._mem_wb.valid, _mem_wb_valid_hold, "stall holds MEM/WB valid");

    @(negedge _clk);
    _dbus.rsp.ready = 1'b1;
    _dbus.rsp.read_data = 32'ha5a5_5a5a;

    @(posedge _clk);
    #1;
    expect_bit(_dut._pipe_en, 1'b1, "data ready releases pipeline stall");
    expect_word(_dut._reg_file._regs[5], 32'h1234_5008, "WB writes auipc result to x5");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures load valid");
    expect_word(_dut._mem_wb.result, 32'ha5a5_5a5a, "MEM/WB captures load result");
    expect_regaddr(_dut._mem_wb.rd, 5'd6, "MEM/WB captures load rd");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[6], 32'ha5a5_5a5a, "WB writes load result to x6");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0010_0073;  // ebreak

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures illegal instruction fetch");
    expect_word(_dut._fetched.instr.raw, 32'h0010_0073, "IFU captures illegal instruction");
    expect_bit(_halted, 1'b0, "illegal fetch does not halt before decode");

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures illegal instruction");
    expect_word(_dut._if_id.instr.raw, 32'h0010_0073, "IF/ID holds illegal instruction");
    expect_bit(_halted, 1'b0, "illegal instruction waits one cycle in IF/ID");

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b1, "valid illegal instruction halts core");
    expect_bit(_dut._pipe_en, 1'b0, "halt disables pipeline");
    expect_bit(_ibus.req.valid, 1'b0, "halt suppresses instruction request");

    _pc_hold                = _pc;
    _if_id_pc_hold          = _dut._if_id.pc;
    _if_id_instr_hold       = _dut._if_id.instr.raw;
    _if_id_valid_hold       = _dut._if_id.valid;
    _id_ex_pc_hold          = _dut._id_ex.pc;
    _id_ex_instr_hold       = _dut._id_ex.instr.raw;
    _id_ex_valid_hold       = _dut._id_ex.valid;
    _ex_mem_alu_result_hold = _dut._ex_mem.alu_result;
    _ex_mem_rd_hold         = _dut._ex_mem.rd;
    _ex_mem_valid_hold      = _dut._ex_mem.valid;
    _mem_wb_result_hold     = _dut._mem_wb.result;
    _mem_wb_rd_hold         = _dut._mem_wb.rd;
    _mem_wb_valid_hold      = _dut._mem_wb.valid;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b1, "halt remains set");
    expect_word(_pc, _pc_hold, "halt holds pc");
    expect_word(_dut._if_id.pc, _if_id_pc_hold, "halt holds IF/ID pc");
    expect_word(_dut._if_id.instr.raw, _if_id_instr_hold, "halt holds IF/ID instr");
    expect_bit(_dut._if_id.valid, _if_id_valid_hold, "halt holds IF/ID valid");
    expect_word(_dut._id_ex.pc, _id_ex_pc_hold, "halt holds ID/EX pc");
    expect_word(_dut._id_ex.instr.raw, _id_ex_instr_hold, "halt holds ID/EX instr");
    expect_bit(_dut._id_ex.valid, _id_ex_valid_hold, "halt holds ID/EX valid");
    expect_word(_dut._ex_mem.alu_result, _ex_mem_alu_result_hold, "halt holds EX/MEM address");
    expect_regaddr(_dut._ex_mem.rd, _ex_mem_rd_hold, "halt holds EX/MEM rd");
    expect_bit(_dut._ex_mem.valid, _ex_mem_valid_hold, "halt holds EX/MEM valid");
    expect_word(_dut._mem_wb.result, _mem_wb_result_hold, "halt holds MEM/WB result");
    expect_regaddr(_dut._mem_wb.rd, _mem_wb_rd_hold, "halt holds MEM/WB rd");
    expect_bit(_dut._mem_wb.valid, _mem_wb_valid_hold, "halt holds MEM/WB valid");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "second reset clears halted");
    expect_word(_pc, 32'h0000_0000, "second reset clears pc");
    expect_bit(_ibus.req.valid, 1'b0, "second reset clears instruction request");
    expect_bit(_dbus.req.valid, 1'b0, "second reset clears data request");

    _dut._reg_file._regs[2] = 32'hdead_beef;
    _dut._reg_file._regs[7] = 32'hface_beef;
    _dut._reg_file._regs[8] = 32'h1000_0000;

    @(negedge _clk);
    _rst = 1'b0;
    _dbus.rsp.ready = 1'b0;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "store scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "store scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0074_1123;  // sh x7, 2(x8)

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures store fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures store pc");
    expect_word(_dut._fetched.instr.raw, 32'h0074_1123, "IFU captures store instr");
    expect_word(_pc, 32'h0000_0004, "store fetch advances pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures store");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID captures store pc");
    expect_word(_dut._if_id.instr.raw, 32'h0074_1123, "IF/ID captures store instr");

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures store");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures store pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0074_1123, "ID/EX captures store instr");
    expect_sh_ctrl(_dut._id_ex.ctrl, "ID/EX captures sh control");
    expect_word(_dut._id_ex.rs1_data, 32'h1000_0000, "ID/EX captures store base");
    expect_word(_dut._id_ex.rs2_data, 32'hface_beef, "ID/EX captures store data");
    expect_word(_dut._id_ex.imm, 32'h0000_0002, "ID/EX captures store immediate");

    @(posedge _clk);
    #1;
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures store");
    expect_word(_dut._ex_mem.alu_result, 32'h1000_0002, "EX/MEM captures store address");
    expect_word(_dut._ex_mem.write_data, 32'hface_beef, "EX/MEM captures store source data");
    expect_bit(_dbus.req.valid, 1'b1, "store requests data bus");
    expect_bit(_dbus.req.write_en, 1'b1, "store request is write");
    expect_word(_dbus.req.addr, 32'h1000_0002, "store request address");
    expect_word(_dbus.req.write_data, 32'hbeef_0000, "store request write data is lane shifted");
    expect_word({28'b0, _dbus.req.write_mask}, 32'h0000_000c, "store request write mask");
    expect_bit(_dut._pipe_en, 1'b0, "store waits when data bus is not ready");
    expect_bit(_ibus.req.valid, 1'b0, "store stall suppresses instruction request");

    _pc_hold                = _pc;
    _ex_mem_alu_result_hold = _dut._ex_mem.alu_result;
    _ex_mem_rd_hold         = _dut._ex_mem.rd;
    _ex_mem_valid_hold      = _dut._ex_mem.valid;
    _dbus_addr_hold         = _dbus.req.addr;
    _dbus_write_data_hold   = _dbus.req.write_data;
    _dbus_write_mask_hold   = _dbus.req.write_mask;

    @(posedge _clk);
    #1;
    expect_word(_pc, _pc_hold, "store stall holds pc");
    expect_word(_dut._ex_mem.alu_result, _ex_mem_alu_result_hold,
                "store stall holds EX/MEM address");
    expect_regaddr(_dut._ex_mem.rd, _ex_mem_rd_hold, "store stall holds EX/MEM rd");
    expect_bit(_dut._ex_mem.valid, _ex_mem_valid_hold, "store stall holds EX/MEM valid");
    expect_bit(_dbus.req.valid, 1'b1, "store stall keeps data request valid");
    expect_bit(_dbus.req.write_en, 1'b1, "store stall keeps write enabled");
    expect_word(_dbus.req.addr, _dbus_addr_hold, "store stall keeps data address stable");
    expect_word(_dbus.req.write_data, _dbus_write_data_hold, "store stall keeps write data stable");
    expect_word({28'b0, _dbus.req.write_mask}, {28'b0, _dbus_write_mask_hold},
                "store stall keeps write mask stable");

    @(negedge _clk);
    _dbus.rsp.ready = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_dut._pipe_en, 1'b1, "store ready releases pipeline stall");
    expect_word(_dut._reg_file._regs[2], 32'hdead_beef, "store does not write rd field");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "third reset clears halted");
    expect_word(_pc, 32'h0000_0000, "third reset clears pc");
    expect_bit(_ibus.req.valid, 1'b0, "third reset clears instruction request");
    expect_bit(_dbus.req.valid, 1'b0, "third reset clears data request");

    @(negedge _clk);
    _rst = 1'b0;
    _dbus.rsp.ready = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "jal scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "jal scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0100_02ef;  // jal x5, 16

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures jal fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures jal pc");
    expect_word(_dut._fetched.instr.raw, 32'h0100_02ef, "IFU captures jal instr");
    expect_word(_pc, 32'h0000_0004, "jal fetch initially advances pc");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0010_0093;  // wrong-path addi x1, x0, 1

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures jal");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID captures jal pc");
    expect_word(_dut._if_id.instr.raw, 32'h0100_02ef, "IF/ID captures jal instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures first wrong-path fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures first wrong-path pc");
    expect_word(_dut._fetched.instr.raw, 32'h0010_0093, "IFU captures first wrong-path instr");
    expect_word(_pc, 32'h0000_0008, "wrong-path fetch advances pc before jal reaches EX");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0020_0113;  // wrong-path addi x2, x0, 2

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures jal");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures jal pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0100_02ef, "ID/EX captures jal instr");
    expect_jal_ctrl(_dut._id_ex.ctrl, "ID/EX captures jal control");
    expect_word(_dut._alu_result, 32'h0000_0010, "JAL computes redirect target");
    expect_bit(_dut._redirect_en, 1'b1, "JAL asserts redirect");
    expect_word(_dut._redirect_pc, 32'h0000_0010, "JAL redirect pc");
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID temporarily holds wrong-path instr before flush");
    expect_word(_dut._if_id.pc, 32'h0000_0004, "IF/ID wrong-path pc before flush");
    expect_word(_dut._if_id.instr.raw, 32'h0010_0093, "IF/ID wrong-path instr before flush");

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0010, "JAL redirect loads target pc");
    expect_bit(_dut._fetched.valid, 1'b0, "JAL redirect squashes fetched wrong-path response");
    expect_bit(_dut._if_id.valid, 1'b0, "JAL redirect flushes IF/ID");
    expect_bit(_dut._id_ex.valid, 1'b0, "JAL redirect prevents wrong-path decode advance");
    expect_bit(_dut._ex_mem.valid, 1'b1, "JAL redirecting instruction advances to EX/MEM");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_0004, "JAL link value reaches EX/MEM");
    expect_regaddr(_dut._ex_mem.rd, 5'd5, "JAL rd reaches EX/MEM");
    expect_word(_ibus.req.addr, 32'h0000_0010, "post-redirect request uses target pc");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0030_0193;  // target addi x3, x0, 3

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures target fetch after redirect");
    expect_word(_dut._fetched.pc, 32'h0000_0010, "IFU target fetch pc");
    expect_word(_dut._fetched.instr.raw, 32'h0030_0193, "IFU target fetch instr");
    expect_bit(_dut._mem_wb.valid, 1'b1, "JAL reaches MEM/WB");
    expect_word(_dut._mem_wb.result, 32'h0000_0004, "JAL link value reaches MEM/WB");
    expect_regaddr(_dut._mem_wb.rd, 5'd5, "JAL rd reaches MEM/WB");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[5], 32'h0000_0004, "WB writes JAL link to x5");
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures target instruction");
    expect_word(_dut._if_id.pc, 32'h0000_0010, "IF/ID captures target pc");
    expect_word(_dut._if_id.instr.raw, 32'h0030_0193, "IF/ID captures target instr");
    expect_word(_dut._reg_file._regs[1], 32'h4444_6666, "wrong-path x1 write is not committed");
    expect_word(_dut._reg_file._regs[2], 32'hdead_beef, "wrong-path x2 write is not committed");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "branch reset clears halted");
    expect_word(_pc, 32'h0000_0000, "branch reset clears pc");

    _dut._reg_file._regs[9]  = 32'h1234_5678;
    _dut._reg_file._regs[10] = 32'h1234_5678;
    _dut._reg_file._regs[12] = 32'hcccc_cccc;
    _dut._reg_file._regs[13] = 32'hdddd_dddd;

    @(negedge _clk);
    _rst = 1'b0;
    _dbus.rsp.ready = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "taken branch scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "taken branch scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h00a4_8863;  // beq x9, x10, 16

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures taken branch fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures taken branch pc");
    expect_word(_dut._fetched.instr.raw, 32'h00a4_8863, "IFU captures taken branch instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00c0_0613;  // wrong-path addi x12, x0, 12

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures taken branch");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID captures taken branch pc");
    expect_word(_dut._if_id.instr.raw, 32'h00a4_8863, "IF/ID captures taken branch instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures taken-branch wrong-path fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures taken-branch wrong-path pc");
    expect_word(_dut._fetched.instr.raw, 32'h00c0_0613,
                "IFU captures taken-branch wrong-path instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00d0_0693;  // wrong-path addi x13, x0, 13

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures taken branch");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures taken branch pc");
    expect_word(_dut._id_ex.instr.raw, 32'h00a4_8863, "ID/EX captures taken branch instr");
    expect_beq_ctrl(_dut._id_ex.ctrl, PC_SRC_IEU_ADR, "ID/EX captures taken beq control");
    expect_word(_dut._id_ex.rs1_data, 32'h1234_5678, "ID/EX captures taken branch rs1");
    expect_word(_dut._id_ex.rs2_data, 32'h1234_5678, "ID/EX captures taken branch rs2");
    expect_word(_dut._id_ex.imm, 32'h0000_0010, "ID/EX captures taken branch immediate");
    expect_word(_dut._alu_result, 32'h0000_0010, "taken branch computes redirect target");
    expect_bit(_dut._redirect_en, 1'b1, "taken branch asserts redirect");
    expect_word(_dut._redirect_pc, 32'h0000_0010, "taken branch redirect pc");

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0010, "taken branch redirect loads target pc");
    expect_bit(_dut._fetched.valid, 1'b0, "taken branch squashes fetched wrong-path response");
    expect_bit(_dut._if_id.valid, 1'b0, "taken branch flushes IF/ID");
    expect_bit(_dut._id_ex.valid, 1'b0, "taken branch prevents wrong-path decode advance");
    expect_bit(_dut._ex_mem.valid, 1'b1, "taken branch advances to EX/MEM");
    expect_word(_ibus.req.addr, 32'h0000_0010, "taken branch request uses target pc");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00e0_0713;  // target addi x14, x0, 14

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures taken branch target fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0010, "IFU taken branch target pc");
    expect_word(_dut._fetched.instr.raw, 32'h00e0_0713, "IFU taken branch target instr");

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures taken branch target");
    expect_word(_dut._if_id.pc, 32'h0000_0010, "IF/ID captures taken branch target pc");
    expect_word(_dut._if_id.instr.raw, 32'h00e0_0713, "IF/ID captures taken branch target instr");
    expect_word(_dut._reg_file._regs[12], 32'hcccc_cccc,
                "taken branch wrong-path x12 write is not committed");
    expect_word(_dut._reg_file._regs[13], 32'hdddd_dddd,
                "taken branch wrong-path x13 write is not committed");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "not-taken branch reset clears halted");
    expect_word(_pc, 32'h0000_0000, "not-taken branch reset clears pc");

    _dut._reg_file._regs[9]  = 32'h1111_1111;
    _dut._reg_file._regs[10] = 32'h2222_2222;

    @(negedge _clk);
    _rst = 1'b0;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "not-taken branch scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "not-taken branch scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h00a4_8863;  // beq x9, x10, 16

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures not-taken branch fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures not-taken branch pc");
    expect_word(_dut._fetched.instr.raw, 32'h00a4_8863, "IFU captures not-taken branch instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00f0_0793;  // fall-through addi x15, x0, 15

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures not-taken branch");
    expect_word(_dut._if_id.instr.raw, 32'h00a4_8863, "IF/ID captures not-taken branch instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures fall-through fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures fall-through pc");
    expect_word(_dut._fetched.instr.raw, 32'h00f0_0793, "IFU captures fall-through instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0100_0813;  // next fall-through addi x16, x0, 16

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures not-taken branch");
    expect_word(_dut._id_ex.instr.raw, 32'h00a4_8863, "ID/EX captures not-taken branch instr");
    expect_beq_ctrl(_dut._id_ex.ctrl, PC_SRC_INC, "ID/EX captures not-taken beq control");
    expect_bit(_dut._redirect_en, 1'b0, "not-taken branch does not redirect");
    expect_bit(_dut._if_id.valid, 1'b1, "not-taken branch keeps fall-through IF/ID");
    expect_word(_dut._if_id.pc, 32'h0000_0004, "not-taken branch keeps fall-through pc");
    expect_word(_dut._if_id.instr.raw, 32'h00f0_0793, "not-taken branch keeps fall-through instr");
    expect_word(_pc, 32'h0000_000c, "not-taken branch continues sequential fetch");

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "fall-through instruction advances after not-taken branch");
    expect_word(_dut._id_ex.pc, 32'h0000_0004, "fall-through ID/EX pc after not-taken branch");
    expect_word(_dut._id_ex.instr.raw, 32'h00f0_0793,
                "fall-through ID/EX instr after not-taken branch");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "jalr reset clears halted");
    expect_word(_pc, 32'h0000_0000, "jalr reset clears pc");

    _dut._reg_file._regs[6]  = 32'h6666_6666;
    _dut._reg_file._regs[11] = 32'h0000_0020;
    _dut._reg_file._regs[17] = 32'h1717_1717;

    @(negedge _clk);
    _rst = 1'b0;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "jalr scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "jalr scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0035_8367;  // jalr x6, 3(x11)

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures jalr fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures jalr pc");
    expect_word(_dut._fetched.instr.raw, 32'h0035_8367, "IFU captures jalr instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0110_0893;  // wrong-path addi x17, x0, 17

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures jalr");
    expect_word(_dut._if_id.instr.raw, 32'h0035_8367, "IF/ID captures jalr instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures jalr wrong-path fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures jalr wrong-path pc");
    expect_word(_dut._fetched.instr.raw, 32'h0110_0893, "IFU captures jalr wrong-path instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00e0_0713;  // stale wrong-path addi x14, x0, 14

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures jalr");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures jalr pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0035_8367, "ID/EX captures jalr instr");
    expect_jalr_ctrl(_dut._id_ex.ctrl, "ID/EX captures jalr control");
    expect_word(_dut._id_ex.rs1_data, 32'h0000_0020, "ID/EX captures jalr base");
    expect_word(_dut._id_ex.imm, 32'h0000_0003, "ID/EX captures jalr immediate");
    expect_word(_dut._alu_result, 32'h0000_0023, "JALR computes raw target");
    expect_bit(_dut._redirect_en, 1'b1, "JALR asserts redirect");
    expect_word(_dut._redirect_pc, 32'h0000_0022, "JALR redirect clears bit zero");

    @(posedge _clk);
    #1;
    expect_word(_pc, 32'h0000_0022, "JALR redirect loads cleared target pc");
    expect_bit(_dut._fetched.valid, 1'b0, "JALR redirect squashes fetched wrong-path response");
    expect_bit(_dut._if_id.valid, 1'b0, "JALR redirect flushes IF/ID");
    expect_bit(_dut._id_ex.valid, 1'b0, "JALR redirect prevents wrong-path decode advance");
    expect_bit(_dut._ex_mem.valid, 1'b1, "JALR advances to EX/MEM");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_0004, "JALR link value reaches EX/MEM");
    expect_regaddr(_dut._ex_mem.rd, 5'd6, "JALR rd reaches EX/MEM");
    expect_word(_ibus.req.addr, 32'h0000_0022, "post-JALR request uses cleared target pc");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h00e0_0713;  // target addi x14, x0, 14

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures JALR target fetch");
    expect_word(_dut._fetched.pc, 32'h0000_0022, "IFU JALR target fetch pc");
    expect_word(_dut._fetched.instr.raw, 32'h00e0_0713, "IFU JALR target fetch instr");
    expect_bit(_dut._mem_wb.valid, 1'b1, "JALR reaches MEM/WB");
    expect_word(_dut._mem_wb.result, 32'h0000_0004, "JALR link value reaches MEM/WB");
    expect_regaddr(_dut._mem_wb.rd, 5'd6, "JALR rd reaches MEM/WB");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[6], 32'h0000_0004, "WB writes JALR link to x6");
    expect_word(_dut._reg_file._regs[17], 32'h1717_1717,
                "JALR wrong-path x17 write is not committed");
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures JALR target instruction");
    expect_word(_dut._if_id.pc, 32'h0000_0022, "IF/ID captures JALR target pc");
    expect_word(_dut._if_id.instr.raw, 32'h00e0_0713, "IF/ID captures JALR target instr");

    @(negedge _clk);
    _rst = 1'b1;
    _ibus.rsp = '0;
    _dbus.rsp = '0;

    @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "data hazard reset clears halted");
    expect_word(_pc, 32'h0000_0000, "data hazard reset clears pc");

    _dut._reg_file._regs[1] = 32'h1111_1111;
    _dut._reg_file._regs[2] = 32'h2222_2222;
    _dut._reg_file._regs[3] = 32'h3333_3333;

    @(negedge _clk);
    _rst = 1'b0;
    _dbus.rsp.ready = 1'b1;

    @(posedge _clk);
    #1;
    expect_bit(_ibus.req.valid, 1'b1, "data hazard scenario requests first instruction");
    expect_word(_ibus.req.addr, 32'h0000_0000, "data hazard scenario starts at address zero");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0050_0093;  // addi x1, x0, 5

    @(posedge _clk);
    #1;
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures hazard producer");
    expect_word(_dut._fetched.pc, 32'h0000_0000, "IFU captures hazard producer pc");
    expect_word(_dut._fetched.instr.raw, 32'h0050_0093, "IFU captures hazard producer instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0010_8133;  // add x2, x1, x1

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures hazard producer");
    expect_word(_dut._if_id.instr.raw, 32'h0050_0093, "IF/ID captures hazard producer instr");
    expect_bit(_dut._fetched.valid, 1'b1, "IFU captures dependent consumer");
    expect_word(_dut._fetched.pc, 32'h0000_0004, "IFU captures dependent consumer pc");
    expect_word(_dut._fetched.instr.raw, 32'h0010_8133, "IFU captures dependent consumer instr");

    @(negedge _clk);
    _ibus.rsp.instr.raw = 32'h0030_0193;  // following addi x3, x0, 3

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures hazard producer");
    expect_word(_dut._id_ex.instr.raw, 32'h0050_0093, "ID/EX captures hazard producer instr");
    expect_regaddr(_dut._id_ex.rd, 5'd1, "ID/EX carries producer rd");
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures dependent consumer");
    expect_word(_dut._if_id.pc, 32'h0000_0004, "IF/ID captures dependent consumer pc");
    expect_word(_dut._if_id.instr.raw, 32'h0010_8133, "IF/ID captures dependent consumer instr");
    expect_bit(_dut._data_stall, 1'b1, "ID/EX producer triggers data stall");
    expect_word(_pc, 32'h0000_000c,
                "prefetched following instruction advances pc before stall is visible");

    _pc_hold          = _pc;
    _if_id_pc_hold    = _dut._if_id.pc;
    _if_id_instr_hold = _dut._if_id.instr.raw;

    @(posedge _clk);
    #1;
    expect_word(_pc, _pc_hold, "data stall holds pc");
    expect_bit(_dut._if_id.valid, 1'b1, "data stall keeps IF/ID valid");
    expect_word(_dut._if_id.pc, _if_id_pc_hold, "data stall holds IF/ID pc");
    expect_word(_dut._if_id.instr.raw, _if_id_instr_hold, "data stall holds IF/ID instr");
    expect_bit(_dut._id_ex.valid, 1'b0, "data stall inserts ID/EX bubble");
    expect_bit(_dut._ex_mem.valid, 1'b1, "data stall lets producer advance to EX/MEM");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_0005,
                "data stall producer result reaches EX/MEM");
    expect_regaddr(_dut._ex_mem.rd, 5'd1, "data stall producer rd reaches EX/MEM");
    expect_bit(_dut._data_stall, 1'b1, "EX/MEM producer keeps data stall asserted");
    expect_bit(_ibus.req.valid, 1'b0, "data stall suppresses instruction request");

    @(posedge _clk);
    #1;
    expect_word(_pc, _pc_hold, "second data stall holds pc");
    expect_bit(_dut._if_id.valid, 1'b1, "second data stall keeps IF/ID valid");
    expect_word(_dut._if_id.instr.raw, _if_id_instr_hold, "second data stall holds IF/ID instr");
    expect_bit(_dut._id_ex.valid, 1'b0, "second data stall keeps ID/EX bubbled");
    expect_bit(_dut._mem_wb.valid, 1'b1, "producer reaches MEM/WB during data stall");
    expect_word(_dut._mem_wb.result, 32'h0000_0005,
                "producer result reaches MEM/WB during data stall");
    expect_regaddr(_dut._mem_wb.rd, 5'd1, "producer rd reaches MEM/WB during data stall");
    expect_bit(_dut._data_stall, 1'b1, "MEM/WB producer keeps conservative data stall asserted");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[1], 32'h0000_0005,
                "producer writes x1 before consumer decode");
    expect_bit(_dut._data_stall, 1'b0, "data stall clears after producer writeback");
    expect_bit(_dut._if_id.valid, 1'b1, "cleared data stall still holds consumer in IF/ID");
    expect_word(_dut._if_id.instr.raw, _if_id_instr_hold,
                "cleared data stall keeps consumer ready for decode");
    expect_bit(_dut._id_ex.valid, 1'b0, "consumer waits one edge after stall clears");

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "consumer advances after hazard clears");
    expect_word(_dut._id_ex.instr.raw, 32'h0010_8133, "consumer reaches ID/EX after hazard clears");
    expect_word(_dut._id_ex.rs1_data, 32'h0000_0005, "consumer reads updated rs1");
    expect_word(_dut._id_ex.rs2_data, 32'h0000_0005, "consumer reads updated rs2");

    @(posedge _clk);
    #1;
    expect_bit(_dut._ex_mem.valid, 1'b1, "consumer advances to EX/MEM");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_000a,
                "consumer computes with updated producer value");
    expect_regaddr(_dut._ex_mem.rd, 5'd2, "consumer rd reaches EX/MEM");

    @(posedge _clk);
    #1;
    expect_bit(_dut._mem_wb.valid, 1'b1, "consumer reaches MEM/WB");
    expect_word(_dut._mem_wb.result, 32'h0000_000a, "consumer result reaches MEM/WB");
    expect_regaddr(_dut._mem_wb.rd, 5'd2, "consumer rd reaches MEM/WB");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[2], 32'h0000_000a, "WB writes dependent consumer result");

    if (errors == 0) begin
      $display("tb_core: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_core: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
