`timescale 1ns / 1ps

module tb_pmp_pkg;
  import riscv_pkg::*;
  import pmp_pkg::*;

  int unsigned _checks = 0;
  int unsigned _errors = 0;
  pmp_state_t _state;

  task automatic expect_allowed(input mem_addr_t addr, input mem_size_e size,
                                input mmu_access_e access, input priv_mode_e privilege,
                                input logic expected, input string what);
    logic got;

    got = pmp_access_allowed(_state, addr, size, access, privilege);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got %0b, expected %0b", what, got, expected);
    end
  endtask

  initial begin
    /* verilator lint_off UNUSEDSIGNAL */
    pmp_cfg_t cfg;
    /* verilator lint_on UNUSEDSIGNAL */

    _state = '0;
    expect_allowed(32'h1234_5678, MEM_SIZE_WORD, MMU_ACCESS_LOAD, PRIV_MACHINE, 1'b1,
                   "M-mode succeeds when no entry matches");
    expect_allowed(32'h1234_5678, MEM_SIZE_WORD, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0,
                   "S-mode defaults deny when entries are implemented");

    // Entry 0: NA4 read-only region at 0x1000.
    _state.cfg[0] = '{locked: 1'b0, reserved: '0, addr_match: PMP_ADDR_NA4,
                      execute: 1'b0, write: 1'b0, read: 1'b1};
    _state.addr[0] = pmp_addr_t'(32'h0000_1000 >> 2);
    expect_allowed(32'h0000_1000, MEM_SIZE_WORD, MMU_ACCESS_LOAD, PRIV_USER, 1'b1,
                   "NA4 permits configured load");
    expect_allowed(32'h0000_1000, MEM_SIZE_WORD, MMU_ACCESS_STORE, PRIV_USER, 1'b0,
                   "NA4 rejects unconfigured store");
    expect_allowed(32'h0000_1000, MEM_SIZE_WORD, MMU_ACCESS_STORE, PRIV_MACHINE, 1'b1,
                   "unlocked entry does not constrain M-mode");
    _state.cfg[0].locked = 1'b1;
    expect_allowed(32'h0000_1000, MEM_SIZE_WORD, MMU_ACCESS_STORE, PRIV_MACHINE, 1'b0,
                   "locked entry constrains M-mode");

    // Entry 1: TOR [0x1004, 0x2000). A halfword crossing its upper bound is
    // rejected because the first overlapping entry must contain every byte.
    _state.cfg[1] = '{locked: 1'b0, reserved: '0, addr_match: PMP_ADDR_TOR,
                      execute: 1'b1, write: 1'b1, read: 1'b1};
    _state.addr[1] = pmp_addr_t'(32'h0000_2000 >> 2);
    expect_allowed(32'h0000_1800, MEM_SIZE_WORD, MMU_ACCESS_FETCH, PRIV_SUPERVISOR, 1'b1,
                   "TOR execute region");
    expect_allowed(32'h0000_1fff, MEM_SIZE_HALF, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0,
                   "partial TOR overlap fails");

    // Entry 2: 16-byte NAPOT region [0x3000, 0x3010).
    _state.cfg[2] = '{locked: 1'b0, reserved: '0, addr_match: PMP_ADDR_NAPOT,
                      execute: 1'b0, write: 1'b1, read: 1'b1};
    _state.addr[2] = pmp_addr_t'((32'h0000_3000 >> 2) | 32'h1);
    expect_allowed(32'h0000_300c, MEM_SIZE_WORD, MMU_ACCESS_STORE, PRIV_USER, 1'b1,
                   "NAPOT includes final word");
    expect_allowed(32'h0000_3010, MEM_SIZE_BYTE, MMU_ACCESS_LOAD, PRIV_USER, 1'b0,
                   "NAPOT excludes upper bound");

    // Lowest-numbered matching entry wins even if a later entry grants more.
    _state.cfg[3] = '{locked: 1'b0, reserved: '0, addr_match: PMP_ADDR_NAPOT,
                      execute: 1'b1, write: 1'b1, read: 1'b1};
    _state.addr[3] = pmp_addr_t'((32'h0000_1000 >> 2) | 32'h1);
    expect_allowed(32'h0000_1000, MEM_SIZE_WORD, MMU_ACCESS_STORE, PRIV_USER, 1'b0,
                   "lower entry has priority");

    cfg = legal_pmp_cfg(8'b1111_1110);
    _checks++;
    if ((cfg.reserved !== '0) || (cfg.write !== 1'b0) || (cfg.read !== 1'b0)) begin
      _errors++;
      $display("  FAIL PMP config WARL legalization");
    end

    if (_errors == 0) begin
      $display("tb_pmp_pkg: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_pmp_pkg: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

endmodule
