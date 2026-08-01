// Directed RV32I architectural coverage for the integrated single-cycle core.
//
// Covers the normal RV32I computational/control/load-store instructions plus
// FENCE as an architectural NOP for this single-hart educational core. ECALL
// and EBREAK require a trap/exception interface and are intentionally not
// claimed here yet.

`timescale 1ns / 1ps

module tb_rv32i
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 200;
  localparam string ProgramFile = "/home/josh/code/riscv-soc/tb/single_stage/tb_rv32i.mem";

  logic   _clk;
  logic   _rst;
  logic   _halted;
  pc_t    _pc;
  pc_t    _imem_addr;
  instr_u _instr;

  int unsigned errors = 0;
  int unsigned checks = 0;

  soc #(
    .ImemDepthWords(128),
    .ImemInitFile  (ProgramFile)
  ) _dut (
    .clk(_clk),
    .rst(_rst),
    .pc(_pc),
    .imem_addr(_imem_addr),
    .instr(_instr),
    .halted(_halted)
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

  task automatic step(input string what);
    @(posedge _clk);
    #1;
    $display("tb_rv32i: %-24s pc=0x%08h imem_addr=0x%08h instr=0x%08h", what, _pc, _imem_addr,
             _instr.raw);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_rv32i);
    end

    _rst = 1'b1;
    step("reset");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;

    repeat (70) step("run");

    expect_word(_dut._core._datapath._regfile._regs[3], 32'h0000_0008, "ADD");
    expect_word(_dut._core._datapath._regfile._regs[4], 32'h0000_0002, "SUB");
    expect_word(_dut._core._datapath._regfile._regs[5], 32'h8001_7fff, "LW after byte/half stores");
    expect_word(_dut._core._datapath._regfile._regs[6], 32'h0000_00dc, "JAL link address");
    expect_word(_dut._core._datapath._regfile._regs[7], 32'h0000_0001, "SLTU");
    expect_word(_dut._core._datapath._regfile._regs[8], 32'h0000_00f5, "JALR odd target source");
    expect_word(_dut._core._datapath._regfile._regs[9], 32'h0000_00ec, "JALR link address");
    expect_word(_dut._core._datapath._regfile._regs[10], 32'h0000_002a, "JALR target executed");
    expect_word(_dut._core._datapath._regfile._regs[11], 32'hffff_ffff, "SRA");
    expect_word(_dut._core._datapath._regfile._regs[12], 32'h0000_0007, "OR");
    expect_word(_dut._core._datapath._regfile._regs[13], 32'h0000_0001, "AND");
    expect_word(_dut._core._datapath._regfile._regs[14], 32'h0000_0001, "SLTI");
    expect_word(_dut._core._datapath._regfile._regs[15], 32'h0000_0000, "SLTIU");
    expect_word(_dut._core._datapath._regfile._regs[16], 32'h0000_0002, "XORI");
    expect_word(_dut._core._datapath._regfile._regs[17], 32'h0000_000d, "ORI");
    expect_word(_dut._core._datapath._regfile._regs[18], 32'h0000_0004, "ANDI");
    expect_word(_dut._core._datapath._regfile._regs[19], 32'h0000_0014, "SLLI");
    expect_word(_dut._core._datapath._regfile._regs[20], 32'h7fff_fffc, "SRLI");
    expect_word(_dut._core._datapath._regfile._regs[21], 32'hffff_fffc, "SRAI");
    expect_word(_dut._core._datapath._regfile._regs[22], 32'h1234_5000, "LUI");
    expect_word(_dut._core._datapath._regfile._regs[23], 32'h0000_0058, "AUIPC");
    expect_word(_dut._core._datapath._regfile._regs[26], 32'hffff_ffff, "LB");
    expect_word(_dut._core._datapath._regfile._regs[27], 32'h0000_007f, "LBU");
    expect_word(_dut._core._datapath._regfile._regs[28], 32'h0000_8001, "SH source");
    expect_word(_dut._core._datapath._regfile._regs[29], 32'hffff_8001, "LH");
    expect_word(_dut._core._datapath._regfile._regs[30], 32'h0000_8001, "LHU");

    expect_word(_dut._dmem._memory[0], 32'h8001_7fff, "SB/SH/SW memory result");
    expect_word(_dut._dmem._memory[1], 32'h0000_0000, "branch failure code remains zero");
    expect_word(_dut._dmem._memory[2], 32'h0000_00ec, "stored JALR link");
    expect_word(_dut._dmem._memory[3], 32'h0000_002a, "stored JALR target result");
    expect_word({31'b0, _halted}, 32'h0, "legal RV32I program does not halt");

    // This is the architectural JALR rule: target bit 0 is cleared before the
    // PC is written. A failure here means the core can still appear to fetch
    // the right instruction because IMEM ignores addr[1:0], but the PC itself
    // is architecturally wrong.
    expect_word({31'b0, _pc[0]}, 32'h0, "JALR clears target bit 0 before writing PC");

    if (errors == 0) begin
      $display("tb_rv32i: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_rv32i: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_rv32i: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
