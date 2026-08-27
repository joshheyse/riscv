// tb_riscv_pkg.sv - package layout checks for shared RISC-V types.
//
//   make sim TB=riscv_pkg
//   make wave TB=riscv_pkg

`timescale 1ns / 1ps

module tb_riscv_pkg
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutSteps = 10;

  int unsigned             errors = 0;
  int unsigned             checks = 0;

  mstatus_t                _mstatus;
  mstatush_t               _mstatush;
  sstatus_t                _sstatus;
  senvcfg_t                _senvcfg;
  menvcfg_t                _menvcfg;
  mip_t                    _mip;
  tvec_t                   _mtvec;
  cause_t                  _cause;
  csr_addr_u               _csr_addr;
  virtual_address_u        _virtual_addr;
  logic             [31:0] _packed;

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
    expect_int($bits(mie_t), 32, "mie_t width");
    expect_int($bits(tvec_t), 32, "tvec_t width");
    expect_int($bits(epc_t), 32, "epc_t width");
    expect_int($bits(cause_t), 32, "cause_t width");
    expect_int($bits(tval_t), 32, "tval_t width");
    expect_int($bits(satp_t), 32, "satp_t width");
    expect_int($bits(virtual_address_fields_t), 32, "virtual address fields width");
    expect_int($bits(virtual_address_u), 32, "virtual address width");
    expect_int($bits(translation_ctx_t), 6, "translation context width");
    expect_int($bits(mmu_req_t), 39, "MMU request width");
    expect_int($bits(mvendorid_t), 32, "mvendorid_t width");
    expect_int($bits(marchid_t), 32, "marchid_t width");
    expect_int($bits(mimpid_t), 32, "mimpid_t width");
    expect_int($bits(mhartid_t), 32, "mhartid_t width");
    expect_int($bits(tvec_mode_e), 2, "tvec_mode_e width");
    expect_int($bits(cause_code_e), 31, "cause_code_e width");
    expect_int($bits(csr_addr_raw_t), 12, "csr_addr_raw_t width");
    expect_int($bits(csr_addr_u), 12, "csr_addr_u width");
    expect_int($bits(csr_addr_fields_t), 12, "csr_addr_fields_t width");
    expect_int($bits(csr_addr_e), 12, "csr_addr_e width");
    expect_int($bits(cbie_e), 2, "cbie_e width");
    expect_int($bits(ext_status_e), 2, "ext_status_e width");
    expect_int($bits(mpp_e), 2, "mpp_e width");
    expect_int($bits(sys_imm_e), 12, "sys_imm_e width");
    expect_int($bits(imm12_u), 12, "imm12_u width");
    expect_int($bits(mmu_fault_e), 2, "mmu_fault_e width");

    expect_bits(32'(CBIE_NONE), 32'h0000_0000, "CBIE none encoding");
    expect_bits(32'(CBIE_FLUSH), 32'h0000_0001, "CBIE flush encoding");
    expect_bits(32'(CBIE_RESERVED), 32'h0000_0002, "CBIE reserved encoding");
    expect_bits(32'(CBIE_INVAL), 32'h0000_0003, "CBIE inval encoding");

    expect_bits(32'(EXT_STATUS_OFF), 32'h0000_0000, "extension status off encoding");
    expect_bits(32'(EXT_STATUS_INITIAL), 32'h0000_0001, "extension status initial encoding");
    expect_bits(32'(EXT_STATUS_CLEAN), 32'h0000_0002, "extension status clean encoding");
    expect_bits(32'(EXT_STATUS_DIRTY), 32'h0000_0003, "extension status dirty encoding");

    expect_bits(32'(MMU_FAULT_NONE), 32'h0000_0000, "MMU no-fault encoding");
    expect_bits(32'(MMU_FAULT_PAGE), 32'h0000_0001, "MMU page-fault encoding");
    expect_bits(32'(MMU_FAULT_ACCESS), 32'h0000_0002, "MMU access-fault encoding");

    expect_bits(32'(MPP_USER), 32'h0000_0000, "MPP user encoding");
    expect_bits(32'(MPP_SUPERVISOR), 32'h0000_0001, "MPP supervisor encoding");
    expect_bits(32'(MPP_MACHINE), 32'h0000_0003, "MPP machine encoding");

    expect_bits(32'(TVEC_MODE_DIRECT), 32'h0000_0000, "tvec direct encoding");
    expect_bits(32'(TVEC_MODE_VECTORED), 32'h0000_0001, "tvec vectored encoding");
    expect_bits(32'(CAUSE_ILLEGAL_INSTR), 32'h0000_0002, "illegal instruction cause encoding");
    expect_bits(32'(CAUSE_INSTR_PAGE_FAULT), 32'h0000_000c,
                "instruction page fault cause encoding");
    expect_bits(32'(CAUSE_LOAD_PAGE_FAULT), 32'h0000_000d, "load page fault cause encoding");
    expect_bits(32'(CAUSE_STORE_PAGE_FAULT), 32'h0000_000f, "store page fault cause encoding");
    expect_bits(32'(SYS_IMM_ECALL), 32'h0000_0000, "SYS_IMM_ECALL encoding");
    expect_bits(32'(SYS_IMM_EBREAK), 32'h0000_0001, "SYS_IMM_EBREAK encoding");
    expect_bits(32'(SYS_IMM_WFI), 32'h0000_0105, "SYS_IMM_WFI encoding");
    expect_bits(32'(SYS_IMM_MRET), 32'h0000_0302, "SYS_IMM_MRET encoding");
    expect_bits(32'(SYS_IMM_SRET), 32'h0000_0102, "SYS_IMM_SRET encoding");

    _virtual_addr.raw = 32'habcd_e123;
    expect_bits(32'(_virtual_addr.named.vpn1), 32'h0000_02af, "virtual address VPN[1] view");
    expect_bits(32'(_virtual_addr.named.vpn0), 32'h0000_00de, "virtual address VPN[0] view");
    expect_bits(32'(_virtual_addr.named.offset), 32'h0000_0123, "virtual address page-offset view");

    expect_bits(32'(CSR_SSTATUS), 32'h0000_0100, "CSR_SSTATUS address");
    expect_bits(32'(CSR_SENVCFG), 32'h0000_010a, "CSR_SENVCFG address");
    expect_bits(32'(CSR_SATP), 32'h0000_0180, "CSR_SATP address");
    expect_bits(32'(CSR_MSTATUS), 32'h0000_0300, "CSR_MSTATUS address");
    expect_bits(32'(CSR_MIE), 32'h0000_0304, "CSR_MIE address");
    expect_bits(32'(CSR_MTVEC), 32'h0000_0305, "CSR_MTVEC address");
    expect_bits(32'(CSR_MENVCFGH), 32'h0000_031a, "CSR_MENVCFGH address");
    expect_bits(32'(CSR_MEPC), 32'h0000_0341, "CSR_MEPC address");
    expect_bits(32'(CSR_MCAUSE), 32'h0000_0342, "CSR_MCAUSE address");
    expect_bits(32'(CSR_MIP), 32'h0000_0344, "CSR_MIP address");
    expect_bits(32'(CSR_MHARTID), 32'h0000_0f14, "CSR_MHARTID address");

    _csr_addr.raw = CSR_MSTATUS;
    expect_bits(32'(_csr_addr.named), 32'(CSR_MSTATUS), "CSR_MSTATUS named view");
    expect_bits(32'(_csr_addr.fields.rw), 32'h0000_0000, "CSR_MSTATUS rw field");
    expect_bits(32'(_csr_addr.fields.min_priv), 32'(PRIV_MACHINE), "CSR_MSTATUS min privilege");
    expect_bits(32'(_csr_addr.fields.index), 32'h0000_0000, "CSR_MSTATUS index field");

    _csr_addr.raw = CSR_SSTATUS;
    expect_bits(32'(_csr_addr.named), 32'(CSR_SSTATUS), "CSR_SSTATUS named view");
    expect_bits(32'(_csr_addr.fields.rw), 32'h0000_0000, "CSR_SSTATUS rw field");
    expect_bits(32'(_csr_addr.fields.min_priv), 32'(PRIV_SUPERVISOR), "CSR_SSTATUS min privilege");
    expect_bits(32'(_csr_addr.fields.index), 32'h0000_0000, "CSR_SSTATUS index field");

    _csr_addr.raw = CSR_SATP;
    expect_bits(32'(_csr_addr.named), 32'(CSR_SATP), "CSR_SATP named view");
    expect_bits(32'(_csr_addr.fields.rw), 32'h0000_0000, "CSR_SATP rw field");
    expect_bits(32'(_csr_addr.fields.min_priv), 32'(PRIV_SUPERVISOR), "CSR_SATP min privilege");
    expect_bits(32'(_csr_addr.fields.index), 32'h0000_0080, "CSR_SATP index field");

    _csr_addr.raw = CSR_MHARTID;
    expect_bits(32'(_csr_addr.named), 32'(CSR_MHARTID), "CSR_MHARTID named view");
    expect_bits(32'(_csr_addr.fields.rw), 32'h0000_0003, "CSR_MHARTID read-only field");
    expect_bits(32'(_csr_addr.fields.min_priv), 32'(PRIV_MACHINE), "CSR_MHARTID min privilege");
    expect_bits(32'(_csr_addr.fields.index), 32'h0000_0014, "CSR_MHARTID index field");

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

    _mtvec = '0;
    _mtvec.base = 30'h0000_1000;
    _packed = _mtvec;
    expect_bits(_packed, 32'h0000_4000, "mtvec.base bits");

    _mtvec = '0;
    _mtvec.mode = TVEC_MODE_VECTORED;
    _packed = _mtvec;
    expect_bits(_packed, 32'h0000_0001, "mtvec.mode bits");

    _cause = '0;
    _cause.is_interrupt = 1'b1;
    _packed = _cause;
    expect_bits(_packed, 32'h8000_0000, "cause.is_interrupt bit");

    _cause = '0;
    _cause.code = CAUSE_ILLEGAL_INSTR;
    _packed = _cause;
    expect_bits(_packed, 32'h0000_0002, "cause.code bits");

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
