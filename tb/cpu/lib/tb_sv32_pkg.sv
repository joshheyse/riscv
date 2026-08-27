// tb_sv32_pkg.sv - directed checks for Sv32 PTE classification and permissions.
//
//   make sim  TB=sv32_pkg
//   make wave TB=sv32_pkg

`timescale 1ns / 1ps

module tb_sv32_pkg;
  import riscv_pkg::*;
  import sv32_pkg::*;

  localparam int unsigned TimeoutNs = 100;

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  sv32_pte_t _pte;
  mmu_req_t  _req;
  satp_t     _satp;

  task automatic expect_logic(input logic got, input logic expected, input string what);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got %b, expected %b", what, got, expected);
    end
  endtask

  task automatic expect_access(input logic expected, input string what);
    expect_logic(leaf_access_allowed(_pte, _req), expected, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_sv32_pkg);
    end

    _pte = '0;
    _req = '0;
    _satp = '0;

    _req.ctx.privilege = PRIV_USER;
    expect_logic(translation_bypassed(_satp, _req.ctx), 1'b1,
                 "Bare mode bypasses user translation");
    _req.ctx.privilege = PRIV_SUPERVISOR;
    expect_logic(translation_bypassed(_satp, _req.ctx), 1'b1,
                 "Bare mode bypasses supervisor translation");
    _satp.mode = 1'b1;
    expect_logic(translation_bypassed(_satp, _req.ctx), 1'b0,
                 "Sv32 translates supervisor accesses");
    _req.ctx.privilege = PRIV_USER;
    expect_logic(translation_bypassed(_satp, _req.ctx), 1'b0,
                 "Sv32 translates user accesses");
    _req.ctx.privilege = PRIV_MACHINE;
    expect_logic(translation_bypassed(_satp, _req.ctx), 1'b1,
                 "Machine privilege bypasses enabled Sv32");

    expect_logic(pte_is_invalid(_pte), 1'b1, "clear PTE is invalid");

    _pte.valid = 1'b1;
    expect_logic(pte_is_invalid(_pte), 1'b0, "valid non-leaf encoding is not invalid");
    expect_logic(pte_is_leaf(_pte), 1'b0, "R/W/X clear identifies a non-leaf");

    _pte.write = 1'b1;
    expect_logic(pte_is_invalid(_pte), 1'b1, "write without read is invalid");

    _pte.read = 1'b1;
    expect_logic(pte_is_invalid(_pte), 1'b0, "read-write encoding is valid");
    expect_logic(pte_is_leaf(_pte), 1'b1, "readable PTE is a leaf");

    _pte = '0;
    _pte.valid = 1'b1;
    _pte.execute = 1'b1;
    expect_logic(pte_is_leaf(_pte), 1'b1, "execute-only PTE is a leaf");

    _pte.ppn0 = '0;
    expect_logic(leaf_is_misaligned(_pte, 1'b1), 1'b0, "aligned level-1 leaf");
    _pte.ppn0 = 10'b1;
    expect_logic(leaf_is_misaligned(_pte, 1'b1), 1'b1, "misaligned level-1 leaf");
    expect_logic(leaf_is_misaligned(_pte, 1'b0), 1'b0,
                 "level-0 leaf permits nonzero lower PPN");

    _pte = '0;
    expect_logic(nonleaf_has_reserved_bits(_pte), 1'b0, "clear non-leaf reserved fields");
    _pte.dirty = 1'b1;
    expect_logic(nonleaf_has_reserved_bits(_pte), 1'b1, "dirty is reserved on a non-leaf");
    _pte = '0;
    _pte.accessed = 1'b1;
    expect_logic(nonleaf_has_reserved_bits(_pte), 1'b1,
                 "accessed is reserved on a non-leaf");
    _pte = '0;
    _pte.user = 1'b1;
    expect_logic(nonleaf_has_reserved_bits(_pte), 1'b1, "user is reserved on a non-leaf");

    expect_logic(ppn_is_supported(22'h0f_ffff), 1'b1, "PPN fits 32-bit physical address");
    expect_logic(ppn_is_supported(22'h10_0000), 1'b0, "PPN physical bit 32 is unsupported");
    expect_logic(ppn_is_supported(22'h20_0000), 1'b0, "PPN physical bit 33 is unsupported");

    _pte = '0;
    _pte.valid = 1'b1;
    _pte.read = 1'b1;
    _pte.write = 1'b1;
    _pte.execute = 1'b1;
    _pte.accessed = 1'b1;
    _pte.dirty = 1'b1;
    _pte.user = 1'b1;

    _req = '0;
    _req.valid = 1'b1;
    _req.ctx.privilege = PRIV_USER;

    _req.ctx.access = MMU_ACCESS_FETCH;
    expect_access(1'b1, "user fetch from executable user page");
    _pte.execute = 1'b0;
    expect_access(1'b0, "user fetch requires execute permission");
    _pte.execute = 1'b1;

    _req.ctx.access = MMU_ACCESS_LOAD;
    expect_access(1'b1, "user load from readable user page");
    _pte.read = 1'b0;
    _req.ctx.mxr = 1'b0;
    expect_access(1'b0, "execute-only page is not readable without MXR");
    _req.ctx.mxr = 1'b1;
    expect_access(1'b1, "MXR permits load from execute-only page");
    _pte.read = 1'b1;
    _req.ctx.mxr = 1'b0;

    _req.ctx.access = MMU_ACCESS_STORE;
    expect_access(1'b1, "user store to writable user page");
    _pte.write = 1'b0;
    expect_access(1'b0, "user store requires write permission");
    _pte.write = 1'b1;

    _pte.user = 1'b0;
    expect_access(1'b0, "user cannot access supervisor page");
    _pte.user = 1'b1;

    _req.ctx.privilege = PRIV_SUPERVISOR;
    _req.ctx.access = MMU_ACCESS_FETCH;
    _req.ctx.sum = 1'b1;
    expect_access(1'b0, "SUM never permits supervisor fetch from user page");

    _req.ctx.access = MMU_ACCESS_LOAD;
    _req.ctx.sum = 1'b0;
    expect_access(1'b0, "supervisor load from user page requires SUM");
    _req.ctx.sum = 1'b1;
    expect_access(1'b1, "SUM permits supervisor load from user page");

    _req.ctx.access = MMU_ACCESS_STORE;
    _req.ctx.sum = 1'b0;
    expect_access(1'b0, "supervisor store to user page requires SUM");
    _req.ctx.sum = 1'b1;
    expect_access(1'b1, "SUM permits supervisor store to user page");

    _pte.user = 1'b0;
    _req.ctx.sum = 1'b0;
    _req.ctx.access = MMU_ACCESS_FETCH;
    expect_access(1'b1, "supervisor fetch from supervisor page");
    _req.ctx.access = MMU_ACCESS_LOAD;
    expect_access(1'b1, "supervisor load from supervisor page");
    _req.ctx.access = MMU_ACCESS_STORE;
    expect_access(1'b1, "supervisor store to supervisor page");

    _pte.accessed = 1'b0;
    _req.ctx.access = MMU_ACCESS_LOAD;
    expect_access(1'b0, "clear accessed bit rejects leaf access");
    _pte.accessed = 1'b1;

    _pte.dirty = 1'b0;
    _req.ctx.access = MMU_ACCESS_LOAD;
    expect_access(1'b1, "load does not require dirty bit");
    _req.ctx.access = MMU_ACCESS_STORE;
    expect_access(1'b0, "store requires dirty bit");
    _pte.dirty = 1'b1;

    _req.ctx.privilege = PRIV_MACHINE;
    expect_access(1'b0, "machine request must bypass leaf permission helper");

    _req.ctx.privilege = PRIV_SUPERVISOR;
    _req.ctx.access = mmu_access_e'(2'b11);
    expect_access(1'b0, "reserved access type is rejected");

    if (_errors == 0) begin
      $display("tb_sv32_pkg: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_sv32_pkg: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_sv32_pkg: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
