// tb_core_boot_branch.sv - pipelined core regression for crt0-style startup.
//
//   make sim DESIGN=pipelined TB=core_boot_branch
//   make wave DESIGN=pipelined TB=core_boot_branch

`timescale 1ns / 1ps

module tb_core_boot_branch
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 400;
  localparam string ProgramFile =
      "/home/josh/code/riscv-soc/tb/cpu/pipelined/tb_core_boot_branch.mem";

  logic _clk;
  logic _rst;
  logic _halted;
  pc_t  _pc;

  mem_if _mem ();
  irq_if _irq ();

  always_comb begin
    _irq.pending.platform = 16'h0000;
    _irq.pending.meip = 1'b0;
    _irq.pending.seip = 1'b0;
    _irq.pending.mtip = 1'b0;
    _irq.pending.stip = 1'b0;
    _irq.pending.msip = 1'b0;
    _irq.pending.ssip = 1'b0;
    _irq.pending.usip = 1'b0;
  end

  int unsigned       errors = 0;
  int unsigned       checks = 0;
  /* verilator lint_off UNUSEDSIGNAL */
  logic              _mmio_write;
  mem_addr_t         _mmio_write_addr;
  mem_data_t         _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */
  logic              _wrong_path_store;
  word_t             _wrong_path_addr;
  word_t             _wrong_path_data;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        [3:0] _write_mask;
  /* verilator lint_on UNUSEDSIGNAL */

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  tb_core_bus #(
    .Words(64),
    .InitFile(ProgramFile)
  ) _bus (
    .clk(_clk),
    .rst(_rst),
    .mem(_mem),
    .mmio_wait(0),
    .mmio_read_data('0),
    .mmio_write(_mmio_write),
    .mmio_write_addr(_mmio_write_addr),
    .mmio_write_data(_mmio_write_data)
  );

  // Stores are observed at the LSU's own port, before the L1 data cache, which
  // is where the old split `dbus` used to sit.
  assign _write_mask = _dut._data_lsu_cache.req.write_mask;

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bit(input logic got, input logic exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %b, expected %b", $time, what, got, exp);
    end
  endtask

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  always_ff @(posedge _clk) begin
    if (_rst) begin
      _wrong_path_store <= 1'b0;
      _wrong_path_addr  <= '0;
      _wrong_path_data  <= '0;
    end else if (_dut._data_lsu_cache.req.valid && _dut._data_lsu_cache.req.write_en) begin
      _wrong_path_store <= 1'b1;
      _wrong_path_addr  <= _dut._data_lsu_cache.req.addr;
      _wrong_path_data  <= _dut._data_lsu_cache.req.write_data;
    end
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_core_boot_branch);
    end

    _rst = 1'b1;
    repeat (2) @(posedge _clk);
    #1;
    expect_bit(_halted, 1'b0, "reset does not halt");
    expect_word(_pc, 32'h0000_0000, "reset pc");

    @(negedge _clk);
    _rst = 1'b0;

    repeat (200) @(posedge _clk);
    #1;

    expect_bit(_halted, 1'b0, "legal boot branch program does not halt");
    expect_bit(_wrong_path_store, 1'b0, "dependent branch does not retire wrong-path store");
    if (_wrong_path_store) begin
      $display("  INFO wrong-path store addr=0x%08h data=0x%08h", _wrong_path_addr,
               _wrong_path_data);
    end
    expect_word(_dut._reg_file._regs[7], 32'h0000_0001, "taken dependent branch reaches target");
    expect_word(_dut._reg_file._regs[5], 32'h0000_0000, "first branch operand is zero");
    expect_word(_dut._reg_file._regs[6], 32'h0000_0000, "second branch operand is zero");

    if (errors == 0) begin
      $display("tb_core_boot_branch: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display(
          "tb_core_boot_branch: state pc=0x%08h if_id_valid=%b if_id_pc=0x%08h if_id_instr=0x%08h id_ex_valid=%b id_ex_pc=0x%08h id_ex_instr=0x%08h ex_mem_valid=%b mem_wb_valid=%b data_stall=%b redirect_en=%b redirect_pc=0x%08h",
          _pc, _dut._if_id.valid, _dut._if_id.slot.pc, _dut._if_id.slot.instr.raw,
          _dut._id_ex.valid, _dut._id_ex.slot.pc, _dut._id_ex.slot.instr.raw, _dut._ex_mem.valid,
          _dut._mem_wb.valid, _dut._data_stall, _dut._redirect.valid, _dut._redirect.pc);
      $display("tb_core_boot_branch: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_core_boot_branch: TIMEOUT after %0d cycles pc=0x%08h", TimeoutCycles, _pc);
    $fatal(1);
  end

endmodule
