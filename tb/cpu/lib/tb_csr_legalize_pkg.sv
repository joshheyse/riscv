// tb_csr_legalize_pkg.sv - directed checks for CSR WARL/WPRI policy.
//
//   make sim  TB=csr_legalize_pkg
//   make wave TB=csr_legalize_pkg

`timescale 1ns / 1ps

module tb_csr_legalize_pkg;
  import riscv_pkg::*;
  import csr_legalize_pkg::*;

  localparam int unsigned TimeoutNs = 100;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  task automatic expect_bits(input logic [31:0] got, input logic [31:0] expected,
                             input string what);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, got, expected);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_legalize_pkg);
    end

    expect_bits(build_legal_mstatus(32'h0000_0000), 32'h0000_0000, "zero mstatus");
    expect_bits(build_legal_mstatus(32'hffff_ffff), 32'h005e_19aa,
                "mstatus keeps implemented fields");
    expect_bits(build_legal_mstatus(32'h0000_1000), 32'h0000_1800,
                "reserved mpp coerces to machine");
    expect_bits(build_legal_mstatus(32'h0000_0800), 32'h0000_0800,
                "supervisor mpp is retained");
    expect_bits(build_legal_mstatus(32'h0050_0000), 32'h0050_0000,
                "tvm and tsr are retained");
    expect_bits(build_legal_mstatus(32'h8000_0000), 32'h0000_0000,
                "unsupported mstatus fields read zero");

    expect_bits(build_legal_sstatus(32'hffff_ffff), 32'h000c_0122,
                "sstatus keeps implemented supervisor fields");
    expect_bits(build_legal_sstatus(32'h000e_0000), 32'h000c_0000,
                "sstatus keeps sum and mxr but omits mprv");
    expect_bits(build_legal_mie(32'h89ab_cdef), 32'h89ab_cdef, "mie typed write value");
    expect_bits(build_legal_mip(32'h7654_3210), 32'h7654_3210, "mip typed write value");

    expect_bits(build_legal_tvec(32'h1234_5000), 32'h1234_5000, "direct tvec is retained");
    expect_bits(build_legal_tvec(32'h1234_5001), 32'h1234_5000,
                "vectored tvec is coerced to direct");
    expect_bits(build_legal_tvec(32'hffff_ffff), 32'hffff_fffc,
                "reserved tvec mode is coerced to direct");

    expect_bits(build_legal_satp(32'h0000_0000), 32'h0000_0000, "Bare satp");
    expect_bits(build_legal_satp(32'h8048_d159), 32'h8008_d159,
                "Sv32 satp retains mode and PPN but clears ASID");
    expect_bits(build_legal_satp(32'hffff_ffff), 32'h803f_ffff,
                "satp clears all ASID bits");

    expect_bits(build_legal_counteren(32'h0000_0000), 32'h0000_0000,
                "zero counteren");
    expect_bits(build_legal_counteren(32'hffff_ffff), 32'h0000_0007,
                "counteren retains only CY TM and IR");
    expect_bits(build_legal_counteren(32'h0000_0005), 32'h0000_0005,
                "counteren independently retains CY and IR");

    if (_errors == 0) begin
      $display("tb_csr_legalize_pkg: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_csr_legalize_pkg: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_csr_legalize_pkg: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
