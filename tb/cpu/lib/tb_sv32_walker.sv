// tb_sv32_walker.sv - directed tests for the Sv32 page-table walker.
//
//   make sim  TB=sv32_walker
//   make wave TB=sv32_walker

`timescale 1ns / 1ps

module tb_sv32_walker;
  import riscv_pkg::*;

  localparam int unsigned ClockPeriodNs = 10;
  localparam int unsigned TimeoutCycles = 1000;

  logic _clk;
  logic _rst = 1'b1;

  satp_t _satp;
  mmu_if _translation ();
  mem_if _memory (
    .clk(_clk),
    .rst(_rst)
  );

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  sv32_pte_t    _pte;
  virtual_address_u _virtual_addr;

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriodNs / 2) _clk = ~_clk;
  end

  sv32_walker dut (
    .clk(_clk),
    .rst(_rst),
    .satp(_satp),
    .translation(_translation),
    .memory(_memory)
  );

  function automatic mem_addr_t pte_address(input logic [19:0] ppn,
                                             input logic [9:0] vpn);
    return {ppn, vpn, 2'b00};
  endfunction

  task automatic expect_logic(input logic got, input logic expected, input string what);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got %b, expected %b", what, got, expected);
    end
  endtask

  task automatic expect_addr(input mem_addr_t got, input mem_addr_t expected,
                             input string what);
    _checks++;
    if (got !== expected) begin
      _errors++;
      $display("  FAIL %s: got 0x%08h, expected 0x%08h", what, got, expected);
    end
  endtask

  task automatic begin_translation(input mem_addr_t virtual_addr, input mmu_access_t access,
                                   input priv_mode_t privilege, input logic sum, input logic mxr);
    @(negedge _clk);
    _translation.req = '{
      valid: 1'b1,
      virtual_addr: virtual_address_u'(virtual_addr),
      access: access,
      privilege: privilege,
      sum: sum,
      mxr: mxr
    };

    while (!_translation.req_ready) begin
      @(negedge _clk);
    end

    @(posedge _clk);
    @(negedge _clk);
    _translation.req.valid = 1'b0;
  endtask

  task automatic serve_pte(input mem_addr_t expected_addr, input sv32_pte_t pte,
                           input int unsigned refuse_cycles,
                           input int unsigned response_delay_cycles, input string what);
    _memory.req_ready = 1'b0;

    while (!_memory.req.valid) begin
      @(negedge _clk);
    end

    expect_addr(_memory.req.addr, expected_addr, $sformatf("%s request address", what));
    expect_logic(_memory.req.write_en, 1'b0, $sformatf("%s is a read", what));

    repeat (refuse_cycles) begin
      @(negedge _clk);
      expect_logic(_memory.req.valid, 1'b1, $sformatf("%s request held while refused", what));
      expect_addr(_memory.req.addr, expected_addr,
                  $sformatf("%s address held while refused", what));
    end

    _memory.req_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _memory.req_ready = 1'b0;

    repeat (response_delay_cycles) @(negedge _clk);
    _memory.rsp = '{valid: 1'b1, read_data: mem_data_t'(pte)};

    while (!_memory.rsp_ready) begin
      @(negedge _clk);
    end

    @(posedge _clk);
    @(negedge _clk);
    _memory.rsp = '0;
  endtask

  task automatic expect_response(input mmu_fault_t expected_fault,
                                 input mem_addr_t expected_addr,
                                 input int unsigned stall_cycles, input string what);
    _translation.rsp_ready = 1'b0;

    while (!_translation.rsp.valid) begin
      @(negedge _clk);
    end

    expect_logic(_translation.rsp.fault == expected_fault, 1'b1,
                 $sformatf("%s fault", what));
    expect_addr(_translation.rsp.physical_addr, expected_addr,
                $sformatf("%s physical address", what));

    repeat (stall_cycles) begin
      @(negedge _clk);
      expect_logic(_translation.rsp.valid, 1'b1, $sformatf("%s response held", what));
      expect_logic(_translation.rsp.fault == expected_fault, 1'b1,
                   $sformatf("%s fault held", what));
      expect_addr(_translation.rsp.physical_addr, expected_addr,
                  $sformatf("%s address held", what));
    end

    _translation.rsp_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _translation.rsp_ready = 1'b0;
  endtask

  task automatic expect_no_memory_request(input string what);
    expect_logic(_memory.req.valid, 1'b0, what);
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_sv32_walker);
    end

    _satp = '0;
    _translation.req = '0;
    _translation.rsp_ready = 1'b0;
    _memory.req_ready = 1'b0;
    _memory.rsp = '0;

    repeat (3) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    // Bare mode returns the virtual address without touching page tables.
    begin_translation(32'h8123_4567, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    expect_no_memory_request("Bare translation does not access memory");
    expect_response(MMU_FAULT_NONE, 32'h8123_4567, 2, "Bare translation");

    // Effective machine privilege also bypasses an enabled Sv32 translation.
    _satp = '{mode: 1'b1, asid: '0, ppn: 22'h000100};
    begin_translation(32'h9234_5678, MMU_ACCESS_STORE, PRIV_MACHINE, 1'b0, 1'b0);
    expect_no_memory_request("machine translation does not access memory");
    expect_response(MMU_FAULT_NONE, 32'h9234_5678, 0, "machine bypass");

    // A readable level-1 leaf translates a 4 MiB superpage. Exercise request
    // refusal and response backpressure on this walk.
    _virtual_addr.raw = 32'h1234_5678;
    _pte = '0;
    _pte.valid = 1'b1;
    _pte.read = 1'b1;
    _pte.accessed = 1'b1;
    _pte.ppn1 = 12'h001;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 2, 2,
              "level-1 PTE");
    expect_response(MMU_FAULT_NONE,
                    {10'(_pte.ppn1), _virtual_addr.named.vpn0, _virtual_addr.named.offset}, 2,
                    "level-1 superpage");

    // A non-leaf level-1 PTE selects a second page table; its level-0 leaf
    // supplies the complete physical page number.
    _virtual_addr.raw = 32'h4567_89ab;
    _pte = '0;
    _pte.valid = 1'b1;
    _pte.ppn0 = 10'h180;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_FETCH, PRIV_USER, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "level-1 non-leaf PTE");
    _pte = '0;
    _pte.valid = 1'b1;
    _pte.execute = 1'b1;
    _pte.user = 1'b1;
    _pte.accessed = 1'b1;
    _pte.ppn1 = 12'h002;
    _pte.ppn0 = 10'h155;
    serve_pte(pte_address(20'h00180, _virtual_addr.named.vpn0), _pte, 1, 1,
              "level-0 leaf PTE");
    expect_response(MMU_FAULT_NONE,
                    {10'(_pte.ppn1), _pte.ppn0, _virtual_addr.named.offset}, 0,
                    "level-0 translation");

    // Invalid PTEs and permission failures are page faults.
    _virtual_addr.raw = 32'h2000_0123;
    _pte = '0;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "invalid PTE");
    expect_response(MMU_FAULT_PAGE, '0, 0, "invalid PTE");

    _pte = '0;
    _pte.valid = 1'b1;
    _pte.read = 1'b1;
    _pte.user = 1'b1;
    _pte.accessed = 1'b1;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "SUM permission PTE");
    expect_response(MMU_FAULT_PAGE, '0, 0, "supervisor load without SUM");

    // A misaligned superpage and a non-leaf at level 0 are page faults.
    _pte = '0;
    _pte.valid = 1'b1;
    _pte.read = 1'b1;
    _pte.accessed = 1'b1;
    _pte.ppn0 = 10'h001;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "misaligned superpage PTE");
    expect_response(MMU_FAULT_PAGE, '0, 0, "misaligned superpage");

    _pte = '0;
    _pte.valid = 1'b1;
    _pte.ppn0 = 10'h180;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "level-1 pointer for final non-leaf");
    _pte = '0;
    _pte.valid = 1'b1;
    serve_pte(pte_address(20'h00180, _virtual_addr.named.vpn0), _pte, 0, 0,
              "level-0 non-leaf PTE");
    expect_response(MMU_FAULT_PAGE, '0, 0, "non-leaf at final level");

    // Unsupported 34-bit PPNs are access faults. The root case must not issue
    // a memory transaction; the leaf case faults after reading its PTE.
    _satp.ppn = 22'h100000;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    expect_no_memory_request("unsupported root PPN does not access memory");
    expect_response(MMU_FAULT_ACCESS, '0, 0, "unsupported root PPN");

    _satp.ppn = 22'h000100;
    _pte = '0;
    _pte.valid = 1'b1;
    _pte.read = 1'b1;
    _pte.accessed = 1'b1;
    _pte.ppn1 = 12'h400;
    begin_translation(_virtual_addr.raw, MMU_ACCESS_LOAD, PRIV_SUPERVISOR, 1'b0, 1'b0);
    serve_pte(pte_address(_satp.ppn[19:0], _virtual_addr.named.vpn1), _pte, 0, 0,
              "unsupported leaf PPN");
    expect_response(MMU_FAULT_ACCESS, '0, 0, "unsupported leaf PPN");

    if (_errors == 0) begin
      $display("tb_sv32_walker: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_sv32_walker: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_sv32_walker: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
