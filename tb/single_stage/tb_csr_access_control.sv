// tb_csr_access_control.sv - self-checking CSR access policy tests.
//
//   make sim  TB=csr_access_control
//   make wave TB=csr_access_control

`timescale 1ns / 1ps

module tb_csr_access_control
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutSteps = 100;

  logic       _csr_en;
  logic       _csr_write_en;
  csr_addr_t  _csr_addr;
  priv_mode_t _priv_mode;
  logic       _illegal_csr_access;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  csr_access_control _dut (
    .csr_en(_csr_en),
    .csr_write_en(_csr_write_en),
    .csr_addr(_csr_addr),
    .priv_mode(_priv_mode),
    .illegal_csr_access(_illegal_csr_access)
  );

  task automatic expect_bit(input logic got, input logic exp, input string what);
    _checks++;
    if (got !== exp) begin
      _errors++;
      $display("  FAIL [%0t] %s: got %0b, expected %0b", $time, what, got, exp);
    end
  endtask

  task automatic check(input logic csr_en, input logic csr_write_en, input csr_addr_raw_t csr_addr,
                       input priv_mode_t priv_mode, input logic exp_illegal, input string what);
    _csr_en        = csr_en;
    _csr_write_en  = csr_write_en;
    _csr_addr.raw  = csr_addr;
    _priv_mode     = priv_mode;
    #1;
    expect_bit(_illegal_csr_access, exp_illegal, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_csr_access_control);
    end

    check(1'b0, 1'b1, CSR_MSTATUS, PRIV_USER, 1'b0, "idle access is legal");

    check(1'b1, 1'b0, CSR_MSTATUS, PRIV_MACHINE, 1'b0, "machine reads machine CSR");
    check(1'b1, 1'b1, CSR_MSTATUS, PRIV_MACHINE, 1'b0, "machine writes machine CSR");
    check(1'b1, 1'b0, CSR_MSTATUS, PRIV_SUPERVISOR, 1'b1, "supervisor cannot read machine CSR");
    check(1'b1, 1'b1, CSR_MSTATUS, PRIV_SUPERVISOR, 1'b1, "supervisor cannot write machine CSR");
    check(1'b1, 1'b0, CSR_MSTATUS, PRIV_USER, 1'b1, "user cannot read machine CSR");

    check(1'b1, 1'b0, CSR_SSTATUS, PRIV_MACHINE, 1'b0, "machine reads supervisor CSR");
    check(1'b1, 1'b1, CSR_SSTATUS, PRIV_MACHINE, 1'b0, "machine writes supervisor CSR");
    check(1'b1, 1'b0, CSR_SSTATUS, PRIV_SUPERVISOR, 1'b0, "supervisor reads supervisor CSR");
    check(1'b1, 1'b1, CSR_SSTATUS, PRIV_SUPERVISOR, 1'b0, "supervisor writes supervisor CSR");
    check(1'b1, 1'b0, CSR_SSTATUS, PRIV_USER, 1'b1, "user cannot read supervisor CSR");

    check(1'b1, 1'b0, CSR_SATP, PRIV_MACHINE, 1'b0, "machine reads satp");
    check(1'b1, 1'b1, CSR_SATP, PRIV_MACHINE, 1'b0, "machine writes satp");
    check(1'b1, 1'b0, CSR_SATP, PRIV_SUPERVISOR, 1'b0, "supervisor reads satp");
    check(1'b1, 1'b1, CSR_SATP, PRIV_SUPERVISOR, 1'b0, "supervisor writes satp");
    check(1'b1, 1'b0, CSR_SATP, PRIV_USER, 1'b1, "user cannot read satp");
    check(1'b1, 1'b1, CSR_SATP, PRIV_USER, 1'b1, "user cannot write satp");

    check(1'b1, 1'b0, CSR_MHARTID, PRIV_MACHINE, 1'b0, "machine reads read-only CSR");
    check(1'b1, 1'b1, CSR_MHARTID, PRIV_MACHINE, 1'b1, "machine cannot write read-only CSR");
    check(1'b1, 1'b1, CSR_MHARTID, PRIV_SUPERVISOR, 1'b1,
          "lower privilege write to read-only CSR is illegal");

    if (_errors == 0) begin
      $display("tb_csr_access_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_csr_access_control: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutSteps);
    $display("tb_csr_access_control: TIMEOUT");
    $fatal(1);
  end

endmodule
