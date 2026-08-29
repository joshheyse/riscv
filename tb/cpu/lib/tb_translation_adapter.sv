// tb_translation_adapter.sv - directed ready/valid tests for virtual-to-physical bridging.
//
//   make sim  TB=translation_adapter
//   make wave TB=translation_adapter

`timescale 1ns / 1ps

module tb_translation_adapter;
  import riscv_pkg::*;

  localparam int unsigned ClockPeriodNs = 10;
  localparam int unsigned TimeoutCycles = 500;

  logic _clk;
  logic _rst;

  translation_ctx_t _ctx;
  satp_t             _satp;

  vmem_if _upstream (
    .clk(_clk),
    .rst(_rst)
  );
  mmu_if _translation ();
  mem_if _downstream (
    .clk(_clk),
    .rst(_rst)
  );

  int unsigned _errors = 0;
  int unsigned _checks = 0;

  initial begin
    _clk = 1'b0;
    forever #(ClockPeriodNs / 2) _clk = ~_clk;
  end

  translation_adapter dut (
    .clk(_clk),
    .rst(_rst),
    .satp(_satp),
    .ctx(_ctx),
    .upstream(_upstream),
    .translation(_translation),
    .downstream(_downstream)
  );

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

  task automatic begin_request(input vmem_req_t req, input translation_ctx_t request_ctx);
    @(negedge _clk);
    _ctx = request_ctx;
    _upstream.req = req;
    _upstream.req.valid = 1'b1;
    #1ps;

    while (!_upstream.req_ready) begin
      @(negedge _clk);
    end

    @(posedge _clk);
    @(negedge _clk);
    _upstream.req.valid = 1'b0;
  endtask

  task automatic accept_translation(input mem_addr_t expected_virtual_addr,
                                    input translation_ctx_t expected_ctx,
                                    input int unsigned refuse_cycles);
    _translation.req_ready = 1'b0;

    while (!_translation.req.valid) begin
      @(negedge _clk);
    end

    expect_addr(_translation.req.virtual_addr.raw, expected_virtual_addr,
                "translation virtual address");
    expect_logic(_translation.req.ctx == expected_ctx, 1'b1, "latched translation context");

    repeat (refuse_cycles) begin
      @(negedge _clk);
      expect_logic(_translation.req.valid, 1'b1, "translation request held while refused");
      expect_addr(_translation.req.virtual_addr.raw, expected_virtual_addr,
                  "translation address held while refused");
      expect_logic(_translation.req.ctx == expected_ctx, 1'b1,
                   "translation context held while refused");
    end

    _translation.req_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _translation.req_ready = 1'b0;
  endtask

  task automatic return_translation(input mmu_fault_e fault, input mem_addr_t physical_addr,
                                    input int unsigned delay_cycles);
    repeat (delay_cycles) @(negedge _clk);
    _translation.rsp = '{valid: 1'b1, fault: fault, physical_addr: physical_addr};

    while (!_translation.rsp_ready) begin
      @(negedge _clk);
    end

    @(posedge _clk);
    @(negedge _clk);
    _translation.rsp = '0;
  endtask

  task automatic accept_physical_request(input mem_addr_t expected_addr,
                                         input logic expected_write_en,
                                         input mem_data_t expected_write_data,
                                         input mem_write_mask_t expected_write_mask,
                                         input int unsigned refuse_cycles);
    _downstream.req_ready = 1'b0;

    while (!_downstream.req.valid) begin
      @(negedge _clk);
    end

    expect_addr(_downstream.req.addr, expected_addr, "physical request address");
    expect_logic(_downstream.req.write_en, expected_write_en,
                 "physical request write enable");
    expect_logic(_downstream.req.write_data == expected_write_data, 1'b1,
                 "physical request write data");
    expect_logic(_downstream.req.write_mask == expected_write_mask, 1'b1,
                 "physical request write mask");

    repeat (refuse_cycles) begin
      @(negedge _clk);
      expect_logic(_downstream.req.valid, 1'b1, "physical request held while refused");
      expect_addr(_downstream.req.addr, expected_addr, "physical address held while refused");
    end

    _downstream.req_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _downstream.req_ready = 1'b0;
  endtask

  task automatic accept_bypass_request(input vmem_req_t req,
                                       input translation_ctx_t request_ctx,
                                       input int unsigned refuse_cycles);
    @(negedge _clk);
    _ctx = request_ctx;
    _upstream.req = req;
    _upstream.req.valid = 1'b1;
    _downstream.req_ready = 1'b0;
    #1ps;

    expect_logic(_downstream.req.valid, 1'b1, "bypass request forwarded");
    expect_logic(_upstream.req_ready, 1'b0, "bypass backpressure propagated");
    repeat (refuse_cycles) begin
      @(negedge _clk);
      expect_logic(_downstream.req.valid, 1'b1, "bypass request held while refused");
      expect_addr(_downstream.req.addr, req.addr, "bypass address held while refused");
    end

    _downstream.req_ready = 1'b1;
    #1ps;
    expect_logic(_upstream.req_ready, 1'b1, "bypass acceptance propagated");
    @(posedge _clk);
    @(negedge _clk);
    _upstream.req.valid = 1'b0;
    _downstream.req_ready = 1'b0;
  endtask

  task automatic return_physical_response(input mem_data_t read_data,
                                          input int unsigned delay_cycles);
    repeat (delay_cycles) @(negedge _clk);
    _downstream.rsp = '{valid: 1'b1, read_data: read_data};

    while (!_downstream.rsp_ready) begin
      @(negedge _clk);
    end

    @(posedge _clk);
    @(negedge _clk);
    _downstream.rsp = '0;
  endtask

  task automatic return_bypass_response(input mem_data_t read_data,
                                        input mem_addr_t expected_physical_addr,
                                        input int unsigned delay_cycles,
                                        input int unsigned stall_cycles,
                                        input string what);
    repeat (delay_cycles) @(negedge _clk);
    _upstream.rsp_ready = 1'b0;
    _downstream.rsp = '{valid: 1'b1, read_data: read_data};
    #1ps;

    expect_logic(_upstream.rsp.valid, 1'b1, $sformatf("%s response forwarded", what));
    expect_logic(_upstream.rsp.fault == MMU_FAULT_NONE, 1'b1,
                 $sformatf("%s fault", what));
    expect_logic(_upstream.rsp.read_data == read_data, 1'b1,
                 $sformatf("%s read data", what));
    expect_addr(_upstream.rsp.physical_addr, expected_physical_addr,
                $sformatf("%s physical address", what));
    expect_logic(_downstream.rsp_ready, 1'b0,
                 $sformatf("%s response backpressure propagated", what));

    repeat (stall_cycles) begin
      @(negedge _clk);
      expect_logic(_upstream.rsp.valid, 1'b1, $sformatf("%s response held", what));
      expect_logic(_upstream.rsp.read_data == read_data, 1'b1,
                   $sformatf("%s data held", what));
    end

    _upstream.rsp_ready = 1'b1;
    #1ps;
    expect_logic(_downstream.rsp_ready, 1'b1,
                 $sformatf("%s response acceptance propagated", what));
    @(posedge _clk);
    @(negedge _clk);
    _upstream.rsp_ready = 1'b0;
    _downstream.rsp = '0;
  endtask

  task automatic expect_upstream_response(input mmu_fault_e expected_fault,
                                          input mem_data_t expected_data,
                                          input mem_addr_t expected_physical_addr,
                                          input int unsigned stall_cycles,
                                          input string what);
    _upstream.rsp_ready = 1'b0;

    while (!_upstream.rsp.valid) begin
      @(negedge _clk);
    end

    expect_logic(_upstream.rsp.fault == expected_fault, 1'b1,
                 $sformatf("%s fault", what));
    expect_logic(_upstream.rsp.read_data == expected_data, 1'b1,
                 $sformatf("%s read data", what));
    expect_addr(_upstream.rsp.physical_addr, expected_physical_addr,
                $sformatf("%s physical address", what));

    repeat (stall_cycles) begin
      @(negedge _clk);
      expect_logic(_upstream.rsp.valid, 1'b1, $sformatf("%s response held", what));
      expect_logic(_upstream.rsp.fault == expected_fault, 1'b1,
                   $sformatf("%s fault held", what));
      expect_logic(_upstream.rsp.read_data == expected_data, 1'b1,
                   $sformatf("%s data held", what));
    end

    _upstream.rsp_ready = 1'b1;
    @(posedge _clk);
    @(negedge _clk);
    _upstream.rsp_ready = 1'b0;
  endtask

  initial begin
    vmem_req_t request;
    translation_ctx_t request_ctx;

    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_translation_adapter);
    end

    _rst = 1'b1;
    _ctx = '0;
    _satp = '{mode: 1'b1, asid: '0, ppn: '0};
    _upstream.req = '0;
    _upstream.rsp_ready = 1'b0;
    _translation.req_ready = 1'b0;
    _translation.rsp = '0;
    _downstream.req_ready = 1'b0;
    _downstream.rsp = '0;

    repeat (3) @(posedge _clk);
    @(negedge _clk);
    _rst = 1'b0;

    expect_logic(_upstream.req_ready, 1'b1, "adapter ready after reset");
    expect_logic(_upstream.rsp.valid, 1'b0, "no virtual response after reset");
    expect_logic(_translation.req.valid, 1'b0, "no translation request after reset");
    expect_logic(_downstream.req.valid, 1'b0, "no physical request after reset");

    // Successful load: context and virtual request must survive translation
    // backpressure, then the physical response must survive upstream refusal.
    request = '{
      valid: 1'b1,
      write_en: 1'b0,
      addr: 32'h8123_4567,
      write_data: '0,
      write_mask: '0
    };
    request_ctx = '{
      access: MMU_ACCESS_LOAD,
      privilege: PRIV_SUPERVISOR,
      sum: 1'b1,
      mxr: 1'b1
    };
    begin_request(request, request_ctx);
    _ctx = '{
      access: MMU_ACCESS_FETCH,
      privilege: PRIV_MACHINE,
      sum: 1'b0,
      mxr: 1'b0
    };
    accept_translation(request.addr, request_ctx, 2);
    return_translation(MMU_FAULT_NONE, 32'h0123_4567, 2);
    accept_physical_request(32'h0123_4567, request.write_en, request.write_data,
                            request.write_mask, 2);
    return_physical_response(32'hdead_beef, 2);
    expect_upstream_response(MMU_FAULT_NONE, 32'hdead_beef, 32'h0123_4567, 2,
                             "successful load");

    // Successful store preserves the write payload and mask.
    request = '{
      valid: 1'b1,
      write_en: 1'b1,
      addr: 32'h4000_0102,
      write_data: 32'ha5c3_7e19,
      write_mask: 4'b0110
    };
    request_ctx = '{
      access: MMU_ACCESS_STORE,
      privilege: PRIV_USER,
      sum: 1'b0,
      mxr: 1'b0
    };
    begin_request(request, request_ctx);
    accept_translation(request.addr, request_ctx, 0);
    return_translation(MMU_FAULT_NONE, 32'h0000_1102, 0);
    accept_physical_request(32'h0000_1102, request.write_en, request.write_data,
                            request.write_mask, 0);
    return_physical_response('0, 0);
    expect_upstream_response(MMU_FAULT_NONE, '0, 32'h0000_1102, 0, "successful store");

    // Translation faults complete upstream without issuing a physical request.
    request = '{
      valid: 1'b1,
      write_en: 1'b0,
      addr: 32'hc000_0123,
      write_data: '0,
      write_mask: '0
    };
    request_ctx = '{
      access: MMU_ACCESS_FETCH,
      privilege: PRIV_USER,
      sum: 1'b0,
      mxr: 1'b0
    };
    begin_request(request, request_ctx);
    accept_translation(request.addr, request_ctx, 1);
    return_translation(MMU_FAULT_PAGE, '0, 1);
    expect_logic(_downstream.req.valid, 1'b0, "page fault bypasses physical memory");
    expect_upstream_response(MMU_FAULT_PAGE, '0, '0, 1, "page fault");

    begin_request(request, request_ctx);
    accept_translation(request.addr, request_ctx, 0);
    return_translation(MMU_FAULT_ACCESS, '0, 0);
    expect_logic(_downstream.req.valid, 1'b0, "access fault bypasses physical memory");
    expect_upstream_response(MMU_FAULT_ACCESS, '0, '0, 0, "access fault");

    // Bare mode skips the translation channel while preserving the complete
    // request payload on the physical channel.
    _satp.mode = 1'b0;
    request = '{
      valid: 1'b1,
      write_en: 1'b1,
      addr: 32'h1234_5004,
      write_data: 32'h7654_3210,
      write_mask: 4'b1010
    };
    request_ctx = '{
      access: MMU_ACCESS_STORE,
      privilege: PRIV_SUPERVISOR,
      sum: 1'b0,
      mxr: 1'b0
    };
    accept_bypass_request(request, request_ctx, 1);
    expect_logic(_translation.req.valid, 1'b0, "Bare mode issues no translation request");
    return_bypass_response('0, request.addr, 0, 1, "Bare-mode store");

    // Machine privilege also bypasses an enabled Sv32 translation.
    _satp.mode = 1'b1;
    request = '{
      valid: 1'b1,
      write_en: 1'b0,
      addr: 32'h89ab_c000,
      write_data: '0,
      write_mask: '0
    };
    request_ctx = '{
      access: MMU_ACCESS_LOAD,
      privilege: PRIV_MACHINE,
      sum: 1'b0,
      mxr: 1'b0
    };
    accept_bypass_request(request, request_ctx, 0);
    expect_logic(_translation.req.valid, 1'b0,
                 "Machine privilege issues no translation request");
    return_bypass_response(32'hfeed_face, request.addr, 0, 0, "Machine-mode load");

    // A zero-cycle physical slave may respond in the request acceptance cycle.
    // The complete bypass must forward that response without entering a wait state.
    @(negedge _clk);
    _upstream.req = request;
    _upstream.req.valid = 1'b1;
    _upstream.rsp_ready = 1'b1;
    _downstream.req_ready = 1'b1;
    _downstream.rsp = '{valid: 1'b1, read_data: 32'h1357_9bdf};
    #1ps;
    expect_logic(_upstream.req_ready, 1'b1, "same-cycle bypass request ready");
    expect_logic(_upstream.rsp.valid, 1'b1, "same-cycle bypass response valid");
    expect_logic(_upstream.rsp.read_data == 32'h1357_9bdf, 1'b1,
                 "same-cycle bypass response data");
    expect_addr(_upstream.rsp.physical_addr, request.addr,
                "same-cycle bypass physical address");
    expect_logic(_downstream.rsp_ready, 1'b1, "same-cycle bypass response ready");
    @(posedge _clk);
    @(negedge _clk);
    _upstream.req = '0;
    _upstream.rsp_ready = 1'b0;
    _downstream.rsp = '0;
    #1ps;
    expect_logic(_upstream.req_ready, 1'b1, "adapter remains idle after same-cycle bypass");
    _downstream.req_ready = 1'b0;

    if (_errors == 0) begin
      $display("tb_translation_adapter: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_translation_adapter: FAIL (%0d failures out of %0d checks)",
             _errors, _checks);
    end
  end

  initial begin
    repeat (TimeoutCycles) @(posedge _clk);
    $display("timeout state=%0d up_valid=%b up_ready=%b down_valid=%b down_ready=%b",
             dut._state, _upstream.req.valid, _upstream.req_ready, _downstream.req.valid,
             _downstream.req_ready);
    $fatal(1, "tb_translation_adapter: TIMEOUT after %0d cycles", TimeoutCycles);
  end

endmodule
