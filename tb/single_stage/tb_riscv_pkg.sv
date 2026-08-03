// tb_riscv_pkg.sv - package layout checks for shared RISC-V types.
//
//   make sim TB=riscv_pkg
//   make wave TB=riscv_pkg

`timescale 1ns / 1ps

module tb_riscv_pkg
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutSteps = 10;

  int unsigned        errors = 0;
  int unsigned        checks = 0;

  mstatus_t           _mstatus;
  mstatush_t          _mstatush;
  sstatus_t           _sstatus;
  senvcfg_t           _senvcfg;
  menvcfg_t           _menvcfg;
  mip_t               _mip;
  logic        [31:0] _packed;

  task automatic expect_int(input int unsigned got, input int unsigned exp, input string what);
    checks++;
    if (got != exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got %0d, expected %0d", $time, what, got, exp);
    end
  endtask

  task automatic expect_bits(input logic [31:0] got, input logic [31:0] exp, input string what);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL [%0t] %s: got 0x%08h, expected 0x%08h", $time, what, got, exp);
    end
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_riscv_pkg);
    end

    expect_int($bits(mstatus_t), 32, "mstatus_t width");
    expect_int($bits(mstatush_t), 32, "mstatush_t width");
    expect_int($bits(sstatus_t), 32, "sstatus_t width");
    expect_int($bits(senvcfg_t), 32, "senvcfg_t width");
    expect_int($bits(menvcfg_t), 32, "menvcfg_t width");
    expect_int($bits(mip_t), 32, "mip_t width");
    expect_int($bits(cbie_t), 2, "cbie_t width");
    expect_int($bits(ext_status_t), 2, "ext_status_t width");
    expect_int($bits(mpp_t), 2, "mpp_t width");

    expect_bits(32'(CBIE_NONE), 32'h0000_0000, "CBIE none encoding");
    expect_bits(32'(CBIE_FLUSH), 32'h0000_0001, "CBIE flush encoding");
    expect_bits(32'(CBIE_RESERVED), 32'h0000_0002, "CBIE reserved encoding");
    expect_bits(32'(CBIE_INVAL), 32'h0000_0003, "CBIE inval encoding");

    expect_bits(32'(EXT_STATUS_OFF), 32'h0000_0000, "extension status off encoding");
    expect_bits(32'(EXT_STATUS_INITIAL), 32'h0000_0001, "extension status initial encoding");
    expect_bits(32'(EXT_STATUS_CLEAN), 32'h0000_0002, "extension status clean encoding");
    expect_bits(32'(EXT_STATUS_DIRTY), 32'h0000_0003, "extension status dirty encoding");

    expect_bits(32'(MPP_USER), 32'h0000_0000, "MPP user encoding");
    expect_bits(32'(MPP_SUPERVISOR), 32'h0000_0001, "MPP supervisor encoding");
    expect_bits(32'(MPP_MACHINE), 32'h0000_0003, "MPP machine encoding");

    _mstatus = '0;
    _mstatus.sd = 1'b1;
    _packed = _mstatus;
    expect_bits(_packed, 32'h8000_0000, "mstatus.sd bit");

    _mstatus = '0;
    _mstatus.mxr = 1'b1;
    _packed = _mstatus;
    expect_bits(_packed, 32'h0008_0000, "mstatus.mxr bit");

    _mstatus = '0;
    _mstatus.xs = EXT_STATUS_DIRTY;
    _packed = _mstatus;
    expect_bits(_packed, 32'h0001_8000, "mstatus.xs bits");

    _mstatus = '0;
    _mstatus.mpp = MPP_MACHINE;
    _packed = _mstatus;
    expect_bits(_packed, 32'h0000_1800, "mstatus.mpp bits");

    _mstatus = '0;
    _mstatus.mie = 1'b1;
    _packed = _mstatus;
    expect_bits(_packed, 32'h0000_0008, "mstatus.mie bit");

    _mstatush = '0;
    _mstatush.mbe = 1'b1;
    _packed = _mstatush;
    expect_bits(_packed, 32'h0000_0020, "mstatush.mbe bit");

    _mstatush = '0;
    _mstatush.sbe = 1'b1;
    _packed = _mstatush;
    expect_bits(_packed, 32'h0000_0010, "mstatush.sbe bit");

    _sstatus = '0;
    _sstatus.sd = 1'b1;
    _packed = _sstatus;
    expect_bits(_packed, 32'h8000_0000, "sstatus.sd bit");

    _sstatus = '0;
    _sstatus.mxr = 1'b1;
    _packed = _sstatus;
    expect_bits(_packed, 32'h0008_0000, "sstatus.mxr bit");

    _sstatus = '0;
    _sstatus.fs = EXT_STATUS_CLEAN;
    _packed = _sstatus;
    expect_bits(_packed, 32'h0000_4000, "sstatus.fs bits");

    _sstatus = '0;
    _sstatus.vs = EXT_STATUS_DIRTY;
    _packed = _sstatus;
    expect_bits(_packed, 32'h0000_0600, "sstatus.vs bits");

    _sstatus = '0;
    _sstatus.sie = 1'b1;
    _packed = _sstatus;
    expect_bits(_packed, 32'h0000_0002, "sstatus.sie bit");

    _senvcfg = '0;
    _senvcfg.cbze = 1'b1;
    _packed = _senvcfg;
    expect_bits(_packed, 32'h0000_0080, "senvcfg.cbze bit");

    _senvcfg = '0;
    _senvcfg.cbie = CBIE_INVAL;
    _packed = _senvcfg;
    expect_bits(_packed, 32'h0000_0030, "senvcfg.cbie bits");

    _senvcfg = '0;
    _senvcfg.sse = 1'b1;
    _packed = _senvcfg;
    expect_bits(_packed, 32'h0000_0008, "senvcfg.sse bit");

    _senvcfg = '0;
    _senvcfg.lpe = 1'b1;
    _packed = _senvcfg;
    expect_bits(_packed, 32'h0000_0004, "senvcfg.lpe bit");

    _menvcfg = '0;
    _menvcfg.cbcfe = 1'b1;
    _packed = _menvcfg;
    expect_bits(_packed, 32'h0000_0040, "menvcfg.cbcfe bit");

    _menvcfg = '0;
    _menvcfg.sse = 1'b1;
    _packed = _menvcfg;
    expect_bits(_packed, 32'h0000_0008, "menvcfg.sse bit");

    _menvcfg = '0;
    _menvcfg.lpe = 1'b1;
    _packed = _menvcfg;
    expect_bits(_packed, 32'h0000_0004, "menvcfg.lpe bit");

    _menvcfg = '0;
    _menvcfg.fiom = 1'b1;
    _packed = _menvcfg;
    expect_bits(_packed, 32'h0000_0001, "menvcfg.fiom bit");

    _mip = '0;
    _mip.meip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0800, "mip.meip bit");

    _mip = '0;
    _mip.seip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0200, "mip.seip bit");

    _mip = '0;
    _mip.mtip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0080, "mip.mtip bit");

    _mip = '0;
    _mip.stip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0020, "mip.stip bit");

    _mip = '0;
    _mip.msip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0008, "mip.msip bit");

    _mip = '0;
    _mip.ssip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0002, "mip.ssip bit");

    _mip = '0;
    _mip.usip = 1'b1;
    _packed = _mip;
    expect_bits(_packed, 32'h0000_0001, "mip.usip bit");

    if (errors == 0) begin
      $display("tb_riscv_pkg: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_riscv_pkg: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutSteps) #1;
    $display("tb_riscv_pkg: TIMEOUT after %0d steps", TimeoutSteps);
    $fatal(1);
  end

endmodule
