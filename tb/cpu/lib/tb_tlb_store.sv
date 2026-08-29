// tb_tlb_store.sv - directed checks for associative Sv32 TLB storage.
//
//   make sim  TB=tlb_store
//   make wave TB=tlb_store

`timescale 1ns / 1ps

module tb_tlb_store;
  import riscv_pkg::*;

  localparam time ClockPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 100;

  logic           _clk;
  logic           _rst;
  tlb_flush_req_t _flush;
  logic           _we;
  sv32_vpn_t      _vpn;
  sv32_asid_t     _asid;
  sv32_level_e    _write_level;
  sv32_pte_t      _write_pte;
  logic           _hit;
  sv32_level_e    _read_level;
  sv32_pte_t      _read_pte;

  int unsigned    _errors = 0;
  int unsigned    _checks = 0;

  tlb_store #(
    .TlbNumEntries(4)
  ) dut (
    .clk(_clk),
    .rst(_rst),
    .flush(_flush),
    .we(_we),
    .vpn(_vpn),
    .asid(_asid),
    .write_level(_write_level),
    .write_pte(_write_pte),
    .hit(_hit),
    .read_level(_read_level),
    .read_pte(_read_pte)
  );

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriod / 2) _clk = ~_clk;
  end

  task automatic expect_logic(input logic got, input logic expected, input string what);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got %b, expected %b", what, got, expected);
    end
  endtask

  task automatic expect_hit(input sv32_level_e expected_level, input sv32_pte_t expected_pte,
                            input string what);
    #1ps;
    expect_logic(_hit, 1'b1, $sformatf("%s hit", what));
    expect_logic(_read_level == expected_level, 1'b1, $sformatf("%s level", what));
    expect_logic(_read_pte == expected_pte, 1'b1, $sformatf("%s PTE", what));
  endtask

  task automatic expect_miss(input string what);
    #1ps;
    expect_logic(_hit, 1'b0, what);
  endtask

  task automatic write_entry(input sv32_vpn_t vpn, input sv32_asid_t asid, input sv32_level_e level,
                             input sv32_pte_t pte);
    @(negedge _clk);
    _vpn = vpn;
    _asid = asid;
    _write_level = level;
    _write_pte = pte;
    _we = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _we = 1'b0;
  endtask

  task automatic flush_entries(input tlb_flush_req_t flush_req);
    @(negedge _clk);
    _flush = flush_req;
    @(posedge _clk);
    @(negedge _clk);
    _flush = '0;
  endtask

  initial begin
    sv32_vpn_t level_0_vpn;
    sv32_vpn_t second_level_0_vpn;
    sv32_vpn_t third_level_0_vpn;
    sv32_vpn_t fourth_level_0_vpn;
    sv32_vpn_t level_1_vpn;
    sv32_pte_t level_0_pte;
    sv32_pte_t level_1_pte;

    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_tlb_store);
    end

    _rst = 1'b1;
    _flush = '0;
    _we = 1'b0;
    _vpn = '0;
    _asid = '0;
    _write_level = SV32_LEVEL_0;
    _write_pte = '0;

    repeat (2) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;
    expect_miss("reset invalidates all entries");

    level_0_vpn = sv32_vpn_t'(20'h12345);
    level_0_pte = '0;
    level_0_pte.valid = 1'b1;
    level_0_pte.read = 1'b1;
    level_0_pte.accessed = 1'b1;
    level_0_pte.ppn = sv32_ppn_t'(22'h012345);
    write_entry(level_0_vpn, sv32_asid_t'(9'h012), SV32_LEVEL_0, level_0_pte);
    expect_hit(SV32_LEVEL_0, level_0_pte, "level-0 exact lookup");

    _vpn.vpn0 = level_0_vpn.vpn0 + sv32_vpn_index_t'(1);
    expect_miss("level-0 lookup compares VPN[0]");
    _vpn  = level_0_vpn;
    _asid = sv32_asid_t'(9'h013);
    expect_miss("non-global entry requires matching ASID");

    level_1_vpn = sv32_vpn_t'(20'habcde);
    level_1_pte = '0;
    level_1_pte.valid = 1'b1;
    level_1_pte.read = 1'b1;
    level_1_pte.accessed = 1'b1;
    level_1_pte.global_mapping = 1'b1;
    level_1_pte.ppn.ppn1 = 12'h055;
    write_entry(level_1_vpn, sv32_asid_t'(9'h020), SV32_LEVEL_1, level_1_pte);

    _vpn.vpn0 = level_1_vpn.vpn0 + sv32_vpn_index_t'(1);
    _asid = sv32_asid_t'(9'h1ff);
    expect_hit(SV32_LEVEL_1, level_1_pte, "global level-1 lookup");

    _vpn.vpn1 = level_1_vpn.vpn1 + sv32_vpn_index_t'(1);
    expect_miss("level-1 lookup compares VPN[1]");

    second_level_0_vpn = sv32_vpn_t'(20'h23456);
    third_level_0_vpn  = sv32_vpn_t'(20'h34567);
    write_entry(second_level_0_vpn, sv32_asid_t'(9'h012), SV32_LEVEL_0, level_0_pte);
    write_entry(third_level_0_vpn, sv32_asid_t'(9'h013), SV32_LEVEL_0, level_0_pte);

    // rs1 != x0, rs2 == x0: invalidate one address for every ASID.
    _vpn   = level_0_vpn;
    _asid  = sv32_asid_t'(9'h012);
    _flush = '{valid: 1'b1, all_vpns: 1'b0, vpn: level_0_vpn, all_asids: 1'b1, asid: '0};
    expect_miss("flush blocks same-cycle lookup");
    flush_entries(_flush);
    expect_miss("address-only flush removes matching level-0 entry");
    _vpn = second_level_0_vpn;
    expect_hit(SV32_LEVEL_0, level_0_pte, "address-only flush preserves another VPN");

    // rs1 == x0, rs2 != x0: invalidate every address for one ASID.
    flush_entries('{valid: 1'b1, all_vpns: 1'b1, vpn: '0, all_asids: 1'b0,
                  asid: sv32_asid_t'(9'h012)});
    expect_miss("ASID-only flush removes matching ASID");
    _vpn  = third_level_0_vpn;
    _asid = sv32_asid_t'(9'h013);
    expect_hit(SV32_LEVEL_0, level_0_pte, "ASID-only flush preserves another ASID");

    // rs1 != x0, rs2 != x0: invalidate the selected address-space mapping.
    flush_entries('{valid: 1'b1, all_vpns: 1'b0, vpn: third_level_0_vpn, all_asids: 1'b0,
                  asid: sv32_asid_t'(9'h013)});
    expect_miss("VPN-and-ASID flush removes selected mapping");

    // An ASID-scoped fence never removes a global mapping.
    _vpn  = level_1_vpn;
    _asid = sv32_asid_t'(9'h1ff);
    flush_entries('{valid: 1'b1, all_vpns: 1'b1, vpn: '0, all_asids: 1'b0,
                  asid: sv32_asid_t'(9'h020)});
    expect_hit(SV32_LEVEL_1, level_1_pte, "ASID flush preserves global mapping");

    // An address-scoped fence matches every address inside a megapage.
    _vpn.vpn0 = level_1_vpn.vpn0 + sv32_vpn_index_t'(1);
    flush_entries('{valid: 1'b1, all_vpns: 1'b0, vpn: _vpn, all_asids: 1'b1, asid: '0});
    expect_miss("address flush matches level-1 megapage by VPN[1]");

    write_entry(level_1_vpn, sv32_asid_t'(9'h020), SV32_LEVEL_1, level_1_pte);
    _vpn = level_1_vpn;
    flush_entries('{valid: 1'b1, all_vpns: 1'b1, vpn: '0, all_asids: 1'b1, asid: '0});
    expect_miss("full flush invalidates stored entries");

    // Fill the store, invalidate a non-victim slot, then refill. The new
    // mapping must occupy the hole instead of evicting the round-robin victim.
    fourth_level_0_vpn = sv32_vpn_t'(20'h45678);
    write_entry(level_0_vpn, sv32_asid_t'(9'h012), SV32_LEVEL_0, level_0_pte);
    write_entry(second_level_0_vpn, sv32_asid_t'(9'h012), SV32_LEVEL_0, level_0_pte);
    write_entry(third_level_0_vpn, sv32_asid_t'(9'h013), SV32_LEVEL_0, level_0_pte);
    write_entry(level_1_vpn, sv32_asid_t'(9'h020), SV32_LEVEL_1, level_1_pte);
    flush_entries('{valid: 1'b1, all_vpns: 1'b0, vpn: third_level_0_vpn, all_asids: 1'b0,
                  asid: sv32_asid_t'(9'h013)});
    write_entry(fourth_level_0_vpn, sv32_asid_t'(9'h014), SV32_LEVEL_0, level_0_pte);

    _vpn  = level_0_vpn;
    _asid = sv32_asid_t'(9'h012);
    expect_hit(SV32_LEVEL_0, level_0_pte, "invalid-first refill preserves valid victim");
    _vpn  = fourth_level_0_vpn;
    _asid = sv32_asid_t'(9'h014);
    expect_hit(SV32_LEVEL_0, level_0_pte, "invalid-first refill occupies hole");

    if (_errors == 0) begin
      $display("tb_tlb_store: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_tlb_store: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_tlb_store: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
