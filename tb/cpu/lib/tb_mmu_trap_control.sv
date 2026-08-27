// tb_mmu_trap_control.sv - MMU fault/access to architectural trap-source mapping.

`timescale 1ns / 1ps

module tb_mmu_trap_control;
  import riscv_pkg::*;

  mmu_fault_t  _fault;
  mmu_access_t _access;
  mem_addr_t   _virtual_addr;
  trap_req_t   _trap_req;

  int unsigned _checks = 0;
  int unsigned _errors = 0;

  mmu_trap_control dut (
    .fault(_fault),
    .access(_access),
    .virtual_addr(_virtual_addr),
    .trap_req(_trap_req)
  );

  task automatic check(input mmu_fault_t fault, input mmu_access_t access,
                       input logic expected_valid, input trap_src_t expected_src,
                       input string what);
    _fault = fault;
    _access = access;
    _virtual_addr = 32'h8123_4567;
    #1;
    _checks++;
    if (_trap_req.valid !== expected_valid || _trap_req.src !== expected_src ||
        _trap_req.tval !== _virtual_addr) begin
      _errors++;
      $error("%s: got valid=%b src=%0d tval=%h", what, _trap_req.valid,
             _trap_req.src, _trap_req.tval);
    end
  endtask

  initial begin
    check(MMU_FAULT_NONE, MMU_ACCESS_FETCH, 1'b0, TRAP_SRC_NONE, "no fault");
    check(MMU_FAULT_PAGE, MMU_ACCESS_FETCH, 1'b1, TRAP_SRC_INSTR_PAGE_FAULT,
          "instruction page fault");
    check(MMU_FAULT_PAGE, MMU_ACCESS_LOAD, 1'b1, TRAP_SRC_LOAD_PAGE_FAULT,
          "load page fault");
    check(MMU_FAULT_PAGE, MMU_ACCESS_STORE, 1'b1, TRAP_SRC_STORE_PAGE_FAULT,
          "store page fault");
    check(MMU_FAULT_ACCESS, MMU_ACCESS_FETCH, 1'b1, TRAP_SRC_INSTR_ACCESS_FAULT,
          "instruction access fault");
    check(MMU_FAULT_ACCESS, MMU_ACCESS_LOAD, 1'b1, TRAP_SRC_LOAD_ACCESS_FAULT,
          "load access fault");
    check(MMU_FAULT_ACCESS, MMU_ACCESS_STORE, 1'b1, TRAP_SRC_STORE_ACCESS_FAULT,
          "store access fault");

    if (_errors == 0) begin
      $display("tb_mmu_trap_control: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_mmu_trap_control: FAIL (%0d failures out of %0d checks)",
             _errors, _checks);
    end
  end

  initial begin
    #100;
    $fatal(1, "tb_mmu_trap_control: TIMEOUT");
  end

endmodule
