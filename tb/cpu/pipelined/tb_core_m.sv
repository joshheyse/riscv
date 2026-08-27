`timescale 1ns / 1ps

module tb_core_m
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_200;

  logic _clk;
  logic _rst;
  logic _halted;
  /* verilator lint_off UNUSEDSIGNAL */
  pc_t  _pc;
  logic _mmio_write;
  mem_addr_t _mmio_write_addr;
  mem_data_t _mmio_write_data;
  /* verilator lint_on UNUSEDSIGNAL */

  mem_if _mem (
    _clk,
    _rst
  );
  irq_if _irq ();

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  assign _irq.pending = '0;

  core _dut (
    .clk(_clk),
    .rst(_rst),
    .time_value('0),
    .halted(_halted),
    .pc(_pc),
    .mem(_mem),
    .irq(_irq)
  );

  tb_core_bus #(
    .Words(128)
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

  function automatic instr_t encode_m(input logic [2:0] funct3, input logic [4:0] rd,
                                      input logic [4:0] rs1, input logic [4:0] rs2);
    return {7'b0000001, rs2, rs1, funct3, rd, OP_R};
  endfunction

  task automatic expect_word(input word_t got, input word_t exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, got, exp);
    end
  endtask

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL %s: got %b, expected %b", what, got, exp);
    end
  endtask

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_core_m.vcd");
      $dumpvars(0, tb_core_m);
    end

    _rst = 1'b1;
    for (int unsigned i = 0; i < 128; i++) begin
      _bus._store[i] = 32'h0000_0013;  // nop
    end

    _bus._store[0]  = 32'hfff0_0093;  // addi x1,x0,-1
    _bus._store[1]  = 32'h0020_0113;  // addi x2,x0,2
    _bus._store[2]  = encode_m(3'b000, 5'd3, 5'd1, 5'd2);   // mul x3,x1,x2
    _bus._store[3]  = 32'h0011_8213;  // addi x4,x3,1
    _bus._store[4]  = encode_m(3'b001, 5'd5, 5'd1, 5'd2);   // mulh
    _bus._store[5]  = encode_m(3'b010, 5'd6, 5'd1, 5'd1);   // mulhsu
    _bus._store[6]  = encode_m(3'b011, 5'd7, 5'd1, 5'd1);   // mulhu
    _bus._store[7]  = encode_m(3'b100, 5'd8, 5'd1, 5'd2);   // div
    _bus._store[8]  = encode_m(3'b101, 5'd9, 5'd1, 5'd2);   // divu
    _bus._store[9]  = encode_m(3'b110, 5'd10, 5'd1, 5'd2);  // rem
    _bus._store[10] = encode_m(3'b111, 5'd11, 5'd1, 5'd2);  // remu
    _bus._store[11] = encode_m(3'b100, 5'd12, 5'd2, 5'd0);  // div by zero
    _bus._store[12] = encode_m(3'b101, 5'd13, 5'd2, 5'd0);  // divu by zero
    _bus._store[13] = encode_m(3'b110, 5'd14, 5'd2, 5'd0);  // rem by zero
    _bus._store[14] = encode_m(3'b111, 5'd15, 5'd2, 5'd0);  // remu by zero
    _bus._store[15] = 32'h8000_0837;  // lui x16,0x80000
    _bus._store[16] = 32'hfff0_0893;  // addi x17,x0,-1
    _bus._store[17] = encode_m(3'b100, 5'd18, 5'd16, 5'd17);  // overflow div
    _bus._store[18] = encode_m(3'b110, 5'd19, 5'd16, 5'd17);  // overflow rem
    _bus._store[19] = encode_m(3'b000, 5'd0, 5'd2, 5'd2);    // MUL cannot write x0
    _bus._store[20] = encode_m(3'b000, 5'd20, 5'd2, 5'd2);   // mul x20,x2,x2
    _bus._store[21] = encode_m(3'b000, 5'd21, 5'd20, 5'd2);  // dependent back-to-back mul

    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    repeat (900) @(posedge _clk);
    #1;

    expect_word(_dut._reg_file._regs[0], 32'h0000_0000, "MUL write to x0 is suppressed");
    expect_word(_dut._reg_file._regs[3], 32'hffff_fffe, "MUL");
    expect_word(_dut._reg_file._regs[4], 32'hffff_ffff, "MUL result forwards to consumer");
    expect_word(_dut._reg_file._regs[5], 32'hffff_ffff, "MULH");
    expect_word(_dut._reg_file._regs[6], 32'hffff_ffff, "MULHSU");
    expect_word(_dut._reg_file._regs[7], 32'hffff_fffe, "MULHU");
    expect_word(_dut._reg_file._regs[8], 32'h0000_0000, "DIV");
    expect_word(_dut._reg_file._regs[9], 32'h7fff_ffff, "DIVU");
    expect_word(_dut._reg_file._regs[10], 32'hffff_ffff, "REM");
    expect_word(_dut._reg_file._regs[11], 32'h0000_0001, "REMU");
    expect_word(_dut._reg_file._regs[12], 32'hffff_ffff, "DIV by zero");
    expect_word(_dut._reg_file._regs[13], 32'hffff_ffff, "DIVU by zero");
    expect_word(_dut._reg_file._regs[14], 32'h0000_0002, "REM by zero");
    expect_word(_dut._reg_file._regs[15], 32'h0000_0002, "REMU by zero");
    expect_word(_dut._reg_file._regs[18], 32'h8000_0000, "signed division overflow");
    expect_word(_dut._reg_file._regs[19], 32'h0000_0000, "signed remainder overflow");
    expect_word(_dut._reg_file._regs[20], 32'h0000_0004, "back-to-back MUL producer");
    expect_word(_dut._reg_file._regs[21], 32'h0000_0008, "back-to-back MUL dependency");
    expect_bit(_halted, 1'b0, "M sequence remains legal");

    if (_errors == 0) begin
      $display("tb_core_m: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_core_m: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_core_m: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
