`timescale 1ns / 1ps

// Self-checking tests for the registered physical-side PMP boundary.
//
//   make sim TB=pmp_annotator
//   make wave TB=pmp_annotator

module tb_pmp_annotator;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;
  localparam int unsigned TimeoutCycles = 1_000;

  logic _clk;
  logic _rst;
  pmp_region_state_t _pmp;

  mem_if _upstream (
    _clk,
    _rst
  );
  mem_if _downstream (
    _clk,
    _rst
  );

  int unsigned _checks;
  int unsigned _errors;

  pmp_annotator _dut (
    .clk(_clk),
    .rst(_rst),
    .pmp(_pmp),
    .upstream(_upstream),
    .downstream(_downstream)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  task automatic expect_bit(input logic actual, input logic expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected %0b, got %0b", what, expected, actual);
    end
  endtask

  task automatic expect_word(input logic [31:0] actual, input logic [31:0] expected,
                             input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected 0x%08h, got 0x%08h", what, expected, actual);
    end
  endtask

  task automatic expect_fault(input mmu_fault_e actual, input mmu_fault_e expected,
                              input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected fault %0d, got %0d", what, expected, actual);
    end
  endtask

  task automatic expect_privilege(input priv_mode_e actual, input priv_mode_e expected,
                                  input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected privilege %0d, got %0d", what, expected, actual);
    end
  endtask

  task automatic expect_annotation(input pmp_annotation_t actual,
                                   input pmp_annotation_t expected, input string what);
    _checks++;
    if (actual !== expected) begin
      _errors++;
      $error("%s: expected annotation %b, got %b", what, expected, actual);
    end
  endtask

  task automatic clear_downstream();
    _downstream.req_ready = 1'b0;
    _downstream.rsp = '0;
  endtask

  task automatic finish_response();
    @(posedge _clk);
    #1;
    expect_bit(_upstream.rsp.valid, 1'b0, "response consumed");
    expect_bit(_upstream.req_ready, 1'b1, "annotator returns idle");
  endtask

  initial begin
    localparam pmp_annotation_t ReadExecute = '{
        valid: 1'b1,
        read: 1'b1,
        write: 1'b0,
        execute: 1'b1
    };
    localparam pmp_annotation_t AllPermissions = '{
        valid: 1'b1,
        read: 1'b1,
        write: 1'b1,
        execute: 1'b1
    };

    _clk = 1'b0;
    _rst = 1'b1;
    _pmp = '0;
    _pmp.entries[0] = '{
        valid: 1'b1,
        locked: 1'b0,
        execute: 1'b1,
        write: 1'b0,
        read: 1'b1,
        start: 35'h0000_0010_0,
        end_addr: 35'h0000_0020_0
    };
    _checks = 0;
    _errors = 0;

    _upstream.req = '0;
    _upstream.rsp_ready = 1'b1;
    clear_downstream();

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_pmp_annotator.vcd");
      $dumpvars(0, tb_pmp_annotator);
    end

    repeat (2) @(posedge _clk);
    _rst = 1'b0;
    #1;

    // A supervisor load inside the configured region is forwarded only after
    // the request has been registered.  Its response receives the raw region
    // permissions used later as cacheline metadata.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b0,
        addr: 32'h0000_0104,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_LOAD,
        privilege: PRIV_SUPERVISOR,
        write_data: '0,
        write_mask: '0
    };
    expect_bit(_upstream.req_ready, 1'b1, "allowed request accepted in idle");
    expect_bit(_downstream.req.valid, 1'b0, "request is registered before forwarding");
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_upstream.req_ready, 1'b0, "annotator blocks a second request");
    expect_bit(_downstream.req.valid, 1'b0, "PMP check occupies the check cycle");
    @(posedge _clk);
    #1;
    expect_bit(_downstream.req.valid, 1'b1, "allowed request forwarded");
    expect_word(_downstream.req.addr, 32'h0000_0104, "forwarded address");
    expect_privilege(_downstream.req.privilege, PRIV_SUPERVISOR, "forwarded privilege");
    expect_bit(_downstream.req.access == MMU_ACCESS_LOAD, 1'b1, "forwarded access type");

    _downstream.req_ready = 1'b1;
    _downstream.rsp = '{
        valid: 1'b1,
        read_data: 32'hcafe_babe,
        fault: MMU_FAULT_NONE,
        pmp_annotation: '0
    };
    @(posedge _clk);
    #1;
    clear_downstream();
    expect_bit(_upstream.rsp.valid, 1'b1, "same-cycle response is registered");
    expect_word(_upstream.rsp.read_data, 32'hcafe_babe, "allowed response data");
    expect_fault(_upstream.rsp.fault, MMU_FAULT_NONE, "allowed response fault");
    expect_annotation(_upstream.rsp.pmp_annotation, ReadExecute,
                      "allowed response annotation");
    finish_response();

    // A supervisor store is rejected by the registered check and never
    // appears on the physical request channel.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: 32'h0000_0108,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_STORE,
        privilege: PRIV_SUPERVISOR,
        write_data: 32'hdead_beef,
        write_mask: 4'b1111
    };
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_downstream.req.valid, 1'b0, "denied request is not forwarded");
    @(posedge _clk);
    #1;
    expect_bit(_downstream.req.valid, 1'b0, "denied request remains blocked after check");
    @(posedge _clk);
    #1;
    expect_bit(_upstream.rsp.valid, 1'b1, "denial produces a registered response");
    expect_fault(_upstream.rsp.fault, MMU_FAULT_ACCESS, "denied store fault");
    expect_annotation(_upstream.rsp.pmp_annotation, ReadExecute,
                      "denied store annotation");
    finish_response();

    // A downstream response may arrive later and may be held while the
    // upstream consumer applies backpressure.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b0,
        addr: 32'h0000_010c,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_FETCH,
        privilege: PRIV_SUPERVISOR,
        write_data: '0,
        write_mask: '0
    };
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_downstream.req.valid, 1'b0, "delayed request waits for PMP check");
    @(posedge _clk);
    #1;
    expect_bit(_downstream.req.valid, 1'b1, "delayed request forwarded");
    _downstream.req_ready = 1'b1;
    _downstream.rsp = '0;
    @(posedge _clk);
    #1;
    clear_downstream();
    expect_bit(_downstream.req.valid, 1'b0, "accepted request leaves request channel");
    expect_bit(_upstream.rsp.valid, 1'b0, "response waits for physical memory");

    _downstream.rsp = '{
        valid: 1'b1,
        read_data: 32'h1234_5678,
        fault: MMU_FAULT_NONE,
        pmp_annotation: '0
    };
    _upstream.rsp_ready = 1'b0;
    @(posedge _clk);
    #1;
    _downstream.rsp = '0;
    expect_bit(_upstream.rsp.valid, 1'b1, "delayed response presented upstream");
    expect_word(_upstream.rsp.read_data, 32'h1234_5678, "delayed response data");
    expect_annotation(_upstream.rsp.pmp_annotation, ReadExecute,
                      "delayed response annotation");
    repeat (2) begin
      @(posedge _clk);
      #1;
      expect_bit(_upstream.rsp.valid, 1'b1, "response held under backpressure");
      expect_word(_upstream.rsp.read_data, 32'h1234_5678,
                  "backpressured response remains stable");
    end
    _upstream.rsp_ready = 1'b1;
    finish_response();

    // Machine mode can access an unlocked region even when the requested
    // operation is not present in its raw R/W/X annotation.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: 32'h0000_0110,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_STORE,
        privilege: PRIV_MACHINE,
        write_data: 32'hfeed_face,
        write_mask: 4'b1111
    };
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_downstream.req.valid, 1'b0, "machine request waits for PMP check");
    @(posedge _clk);
    #1;
    expect_bit(_downstream.req.valid, 1'b1, "machine request bypasses unlocked permission");
    _downstream.req_ready = 1'b1;
    _downstream.rsp = '{
        valid: 1'b1,
        read_data: '0,
        fault: MMU_FAULT_NONE,
        pmp_annotation: AllPermissions
    };
    @(posedge _clk);
    #1;
    clear_downstream();
    expect_fault(_upstream.rsp.fault, MMU_FAULT_NONE, "machine request allowed");
    expect_annotation(_upstream.rsp.pmp_annotation, ReadExecute,
                      "machine response retains region annotation");
    finish_response();

    if (_errors == 0) begin
      $display("tb_pmp_annotator: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $display("tb_pmp_annotator: FAIL (%0d failures out of %0d checks)", _errors, _checks);
      $fatal(1);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $fatal(1, "tb_pmp_annotator: watchdog timeout");
  end

endmodule
