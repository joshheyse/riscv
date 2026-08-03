// tb_csr_file.sv - self-checking testbench for the machine CSR file.
//
//   make sim  TB=csr_file
//   make wave TB=csr_file

`timescale 1ns / 1ps

module tb_csr_file
  import riscv_pkg::*;
();

  localparam realtime ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 10_000;

  logic        _clk;
  logic        _rst;
  logic        _csr_en;
  logic        _csr_write_en;
  csr_addr_t   _csr_addr;
  csr_data_t   _csr_write_data;
  logic        _trap_valid;
  mepc_t       _trap_mepc;
  mcause_t     _trap_mcause;
  mtval_t      _trap_mtval;
  csr_data_t   _csr_read_data;
  logic        _illegal_csr;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  csr_file _dut (
    .clk(_clk),
    .rst(_rst),
    .csr_en(_csr_en),
    .csr_write_en(_csr_write_en),
    .csr_addr(_csr_addr),
    .csr_write_data(_csr_write_data),
    .trap_valid(_trap_valid),
    .trap_mepc(_trap_mepc),
    .trap_mcause(_trap_mcause),
    .trap_mtval(_trap_mtval),
    .csr_read_data(_csr_read_data),
    .illegal_csr(_illegal_csr)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClkPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_bits(input logic [31:0] got, input logic [31:0] exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  task automatic expect_bool(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic tick();
    @(negedge _clk);
    @(negedge _clk);
  endtask

  task automatic drive_idle();
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
    _trap_valid = 1'b0;
    _trap_mepc = '0;
    _trap_mcause = '0;
    _trap_mtval = '0;
  endtask

  task automatic read_csr(input csr_addr_t addr, input csr_data_t exp, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b0;
    _csr_addr = addr;
    _csr_write_data = '0;
    #1;
    expect_bool(_illegal_csr, 1'b0, {what, " legal read"});
    expect_bits(_csr_read_data, exp, what);
    @(negedge _clk);
    _csr_en   = 1'b0;
    _csr_addr = '0;
  endtask

  task automatic write_csr(input csr_addr_t addr, input csr_data_t data, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr = addr;
    _csr_write_data = data;
    #1;
    expect_bool(_illegal_csr, 1'b0, {what, " legal write"});
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
  endtask

  task automatic expect_illegal_read(input csr_addr_t addr, input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b0;
    _csr_addr = addr;
    #1;
    expect_bool(_illegal_csr, 1'b1, what);
    expect_bits(_csr_read_data, '0, {what, " data"});
    @(negedge _clk);
    _csr_en   = 1'b0;
    _csr_addr = '0;
  endtask

  task automatic expect_illegal_write(input csr_addr_t addr, input csr_data_t data,
                                      input string what);
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr = addr;
    _csr_write_data = data;
    #1;
    expect_bool(_illegal_csr, 1'b1, what);
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b0;
    _csr_addr = '0;
    _csr_write_data = '0;
  endtask

  task automatic take_trap(input mepc_t mepc, input mcause_t mcause, input mtval_t mtval);
    @(negedge _clk);
    _trap_valid  = 1'b1;
    _trap_mepc   = mepc;
    _trap_mcause = mcause;
    _trap_mtval  = mtval;
    @(negedge _clk);
    _trap_valid  = 1'b0;
    _trap_mepc   = '0;
    _trap_mcause = '0;
    _trap_mtval  = '0;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_file);
    end

    drive_idle();
    _rst = 1'b1;
    repeat (2) @(negedge _clk);
    _rst = 1'b0;

    // Reset state: writable machine CSRs and read-only ID CSRs all read zero.
    read_csr(CSR_MSTATUS, 32'h0000_0000, "reset mstatus");
    read_csr(CSR_MIE, 32'h0000_0000, "reset mie");
    read_csr(CSR_MTVEC, 32'h0000_0000, "reset mtvec");
    read_csr(CSR_MEPC, 32'h0000_0000, "reset mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0000, "reset mcause");
    read_csr(CSR_MTVAL, 32'h0000_0000, "reset mtval");
    read_csr(CSR_MIP, 32'h0000_0000, "reset mip");
    read_csr(CSR_MVENDORID, 32'h0000_0000, "read mvendorid");
    read_csr(CSR_MARCHID, 32'h0000_0000, "read marchid");
    read_csr(CSR_MIMPID, 32'h0000_0000, "read mimpid");
    read_csr(CSR_MHARTID, 32'h0000_0000, "read mhartid");

    // Idle cycles should not report illegal access even if the address is not
    // implemented.
    @(negedge _clk);
    _csr_en = 1'b0;
    _csr_write_en = 1'b1;
    _csr_addr = 12'hfff;
    #1;
    expect_bool(_illegal_csr, 1'b0, "idle access is not illegal");
    _csr_write_en = 1'b0;

    // Normal writable CSR path.
    write_csr(CSR_MTVEC, 32'h0000_1001, "write mtvec");
    read_csr(CSR_MTVEC, 32'h0000_1001, "read mtvec");

    write_csr(CSR_MEPC, 32'h0000_0040, "write mepc");
    read_csr(CSR_MEPC, 32'h0000_0040, "read mepc");

    write_csr(CSR_MCAUSE, 32'h8000_0007, "write mcause");
    read_csr(CSR_MCAUSE, 32'h8000_0007, "read mcause");

    write_csr(CSR_MTVAL, 32'hdead_beef, "write mtval");
    read_csr(CSR_MTVAL, 32'hdead_beef, "read mtval");

    write_csr(CSR_MIP, 32'h0000_0888, "write mip");
    read_csr(CSR_MIP, 32'h0000_0888, "read mip");

    // Unknown CSRs and read-only ID writes should be illegal.
    expect_illegal_read(12'hfff, "unknown CSR read illegal");
    expect_illegal_write(12'hfff, 32'h1234_5678, "unknown CSR write illegal");
    expect_illegal_write(CSR_MVENDORID, 32'hffff_ffff, "mvendorid write illegal");
    read_csr(CSR_MVENDORID, 32'h0000_0000, "mvendorid unchanged after write");

    // Trap entry updates trap CSRs.
    take_trap(32'h0000_0080, '{is_interrupt: 1'b0, code: MCAUSE_ILLEGAL_INSTR}, 32'h0000_0013);
    read_csr(CSR_MEPC, 32'h0000_0080, "trap writes mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0002, "trap writes mcause");
    read_csr(CSR_MTVAL, 32'h0000_0013, "trap writes mtval");

    // Trap entry wins over a simultaneous normal CSR write.
    @(negedge _clk);
    _csr_en = 1'b1;
    _csr_write_en = 1'b1;
    _csr_addr = CSR_MEPC;
    _csr_write_data = 32'hffff_ffff;
    _trap_valid = 1'b1;
    _trap_mepc = 32'h0000_00c0;
    _trap_mcause = '{is_interrupt: 1'b0, code: MCAUSE_BREAKPOINT};
    _trap_mtval = 32'h0000_00cc;
    #1;
    expect_bool(_illegal_csr, 1'b0, "simultaneous trap/write legal CSR address");
    @(negedge _clk);
    drive_idle();
    read_csr(CSR_MEPC, 32'h0000_00c0, "trap wins over csr write mepc");
    read_csr(CSR_MCAUSE, 32'h0000_0003, "trap wins over csr write mcause");
    read_csr(CSR_MTVAL, 32'h0000_00cc, "trap wins over csr write mtval");

    if (_errors == 0) begin
      $display("tb_csr_file: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_csr_file: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("tb_csr_file: TIMEOUT after %0d cycles", TimeoutCycles);
    $fatal(1);
  end

endmodule
