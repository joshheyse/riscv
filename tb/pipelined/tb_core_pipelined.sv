// tb_core_pipelined.sv - first bring-up checks for the pipelined core.
//
//   make sim DESIGN=pipelined TB=core_pipelined
//   make wave DESIGN=pipelined TB=core_pipelined
//
// This testbench grows one pipeline stage at a time as the implementation
// comes online.

`timescale 1ns / 1ps

module tb_core_pipelined
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 50;

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  ibus_if _ibus ();
  dbus_if _dbus ();

  int unsigned errors = 0;
  int unsigned checks = 0;

  logic        _unused_bus_bits;
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

  core_pipelined _dut (
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

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_pipelined);
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
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0000, "IF/ID captures fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h0050_0093, "IF/ID captures fetched instr");
    expect_word(_pc, 32'h0000_0004, "fetch accept advances pc");
    expect_word(_ibus.req.addr, 32'h0000_0004, "next fetch uses advanced pc");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0000, "ID/EX captures decoded pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0050_0093, "ID/EX captures decoded instr");
    expect_addi_ctrl(_dut._id_ex.ctrl, "ID/EX captures addi control");
    expect_word(_dut._id_ex.rs1_data, 32'h0000_0000, "ID/EX rs1 data stub is zero");
    expect_word(_dut._id_ex.rs2_data, 32'h0000_0000, "ID/EX rs2 data stub is zero");
    expect_word(_dut._id_ex.imm, 32'h0000_0005, "ID/EX captures addi immediate");
    expect_word(_dut._src_a, 32'h0000_0000, "ADDI ALU src_a selects rs1");
    expect_word(_dut._src_b, 32'h0000_0005, "ADDI ALU src_b selects immediate");
    expect_word(_dut._alu_result, 32'h0000_0005, "ADDI ALU result");

    _dut._reg_file._regs[2] = 32'h1111_2222;
    _dut._reg_file._regs[3] = 32'h3333_4444;

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h0031_00b3;  // add x1, x2, x3

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures second valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0004, "IF/ID captures second fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h0031_00b3, "IF/ID captures second fetched instr");
    expect_word(_pc, 32'h0000_0008, "second fetch advances pc");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures addi valid");
    expect_word(_dut._ex_mem.alu_result, 32'h0000_0005, "EX/MEM captures addi raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h0000_0005, "EX/MEM captures addi execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd1, "EX/MEM captures addi rd");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures second valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0004, "ID/EX captures second decoded pc");
    expect_word(_dut._id_ex.instr.raw, 32'h0031_00b3, "ID/EX captures second decoded instr");
    expect_word(_dut._id_ex.rs1_data, 32'h1111_2222, "ID/EX captures rs1 data");
    expect_word(_dut._id_ex.rs2_data, 32'h3333_4444, "ID/EX captures rs2 data");
    expect_word(_dut._src_a, 32'h1111_2222, "ADD ALU src_a selects rs1");
    expect_word(_dut._src_b, 32'h3333_4444, "ADD ALU src_b selects rs2");
    expect_word(_dut._alu_result, 32'h4444_6666, "ADD ALU result");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures addi valid");
    expect_word(_dut._mem_wb.result, 32'h0000_0005, "MEM/WB captures addi result");
    expect_regaddr(_dut._mem_wb.rd, 5'd1, "MEM/WB captures addi rd");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b1;
    _ibus.rsp.instr.raw = 32'h1234_5297;  // auipc x5, 0x12345

    @(posedge _clk);
    #1;
    expect_bit(_dut._if_id.valid, 1'b1, "IF/ID captures third valid fetch");
    expect_word(_dut._if_id.pc, 32'h0000_0008, "IF/ID captures third fetched pc");
    expect_word(_dut._if_id.instr.raw, 32'h1234_5297, "IF/ID captures third fetched instr");
    expect_word(_pc, 32'h0000_000c, "third fetch advances pc");
    expect_word(_dut._reg_file._regs[1], 32'h0000_0005, "WB writes addi result to x1");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures add valid");
    expect_word(_dut._ex_mem.alu_result, 32'h4444_6666, "EX/MEM captures add raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h4444_6666, "EX/MEM captures add execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd1, "EX/MEM captures add rd");

    @(negedge _clk);
    _ibus.rsp.ready = 1'b0;
    _ibus.rsp.instr = '0;

    @(posedge _clk);
    #1;
    expect_bit(_dut._id_ex.valid, 1'b1, "ID/EX captures auipc valid decode");
    expect_word(_dut._id_ex.pc, 32'h0000_0008, "ID/EX captures auipc pc");
    expect_word(_dut._id_ex.instr.raw, 32'h1234_5297, "ID/EX captures auipc instr");
    expect_auipc_ctrl(_dut._id_ex.ctrl, "ID/EX captures auipc control");
    expect_word(_dut._id_ex.imm, 32'h1234_5000, "ID/EX captures auipc immediate");
    expect_word(_dut._src_a, 32'h0000_0008, "AUIPC ALU src_a selects ID/EX pc");
    expect_word(_dut._src_b, 32'h1234_5000, "AUIPC ALU src_b selects ID/EX immediate");
    expect_word(_dut._alu_result, 32'h1234_5008, "AUIPC ALU result");
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures add valid");
    expect_word(_dut._mem_wb.result, 32'h4444_6666, "MEM/WB captures add result");
    expect_regaddr(_dut._mem_wb.rd, 5'd1, "MEM/WB captures add rd");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[1], 32'h4444_6666, "WB writes add result to x1");
    expect_bit(_dut._ex_mem.valid, 1'b1, "EX/MEM captures auipc valid");
    expect_word(_dut._ex_mem.alu_result, 32'h1234_5008, "EX/MEM captures auipc raw ALU result");
    expect_word(_dut._ex_mem.execute_result, 32'h1234_5008, "EX/MEM captures auipc execute result");
    expect_regaddr(_dut._ex_mem.rd, 5'd5, "EX/MEM captures auipc rd");

    @(posedge _clk);
    #1;
    expect_bit(_dut._mem_wb.valid, 1'b1, "MEM/WB captures auipc valid");
    expect_word(_dut._mem_wb.result, 32'h1234_5008, "MEM/WB captures auipc result");
    expect_regaddr(_dut._mem_wb.rd, 5'd5, "MEM/WB captures auipc rd");

    @(posedge _clk);
    #1;
    expect_word(_dut._reg_file._regs[5], 32'h1234_5008, "WB writes auipc result to x5");

    if (errors == 0) begin
      $display("tb_core_pipelined: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_core_pipelined: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_pipelined: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
