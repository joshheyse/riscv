`timescale 1ns / 1ps

module tb_amo_execute
  import riscv_pkg::*;
();

  localparam int unsigned TimeoutNs = 1000;

  logic     _clk;
  logic     _rst;
  amo_req_t _req;
  logic     _req_ready;
  amo_rsp_t _rsp;
  logic     _rsp_ready;
  logic     _reservation_clear;
  int unsigned _checks = 0;
  int unsigned _errors = 0;

  vmem_if _memory_if (
    .clk(_clk),
    .rst(_rst)
  );

  amo_execute _dut (
    .clk(_clk),
    .rst(_rst),
    .req(_req),
    .req_ready(_req_ready),
    .rsp(_rsp),
    .rsp_ready(_rsp_ready),
    .reservation_clear(_reservation_clear),
    .memory(_memory_if.master)
  );

  always #5 _clk = ~_clk;

  task automatic check(input logic condition, input string what);
    _checks++;
    if (!condition) begin
      _errors++;
      $error("%s", what);
    end
  endtask

  task automatic tick;
    @(posedge _clk);
    #1;
  endtask

  task automatic start_request(input amo_op_e op, input virtual_address_u address,
                               input reg_data_t operand);
    @(negedge _clk);
    _req = '{
        valid: 1'b1,
        ctrl: '{en: 1'b1, op: op, aq: 1'b0, rl: 1'b0},
        address: address,
        operand: operand,
        ctx: '0
    };
    check(_req_ready, "executor ready before request");
    tick();
    _req.valid = 1'b0;
  endtask

  task automatic accept_memory_request;
    @(negedge _clk);
    _memory_if.req_ready = 1'b1;
    tick();
    _memory_if.req_ready = 1'b0;
  endtask

  task automatic send_memory_response(input mem_data_t read_data, input mmu_fault_e fault,
                                      input mem_addr_t physical_addr);
    @(negedge _clk);
    _memory_if.rsp = '{
        valid: 1'b1,
        read_data: read_data,
        fault: fault,
        physical_addr: physical_addr
    };
    check(_memory_if.rsp_ready, "executor ready for expected memory response");
    tick();
    _memory_if.rsp = '0;
  endtask

  task automatic consume_amo_response(input reg_data_t expected_result,
                                      input mmu_fault_e expected_fault, input string what);
    check(_rsp.valid, $sformatf("%s response valid", what));
    check(_rsp.result == expected_result, $sformatf("%s result", what));
    check(_rsp.fault == expected_fault, $sformatf("%s fault", what));
    _rsp_ready = 1'b1;
    tick();
    _rsp_ready = 1'b0;
  endtask

  initial begin
    virtual_address_u address;
    vmem_req_t stalled_request;

    _clk = 1'b0;
    if ($test$plusargs("trace")) begin
      $dumpfile("tb_amo_execute.vcd");
      $dumpvars(0, tb_amo_execute);
    end

    _rst = 1'b1;
    _req = '0;
    _rsp_ready = 1'b0;
    _reservation_clear = 1'b0;
    _memory_if.req_ready = 1'b0;
    _memory_if.rsp = '0;
    repeat (2) tick();
    _rst = 1'b0;
    tick();

    address.raw = 32'h1234_5000;
    start_request(AMO_OP_ADD, address, 32'h0000_0007);
    check(_memory_if.req.valid, "read request asserted");
    check(!_memory_if.req.write_en, "first request is a read");
    check(_memory_if.req.addr == address.raw, "read request uses latched address");
    stalled_request = _memory_if.req;

    // A younger AMO may be presented, but it cannot transfer or replace the
    // active operation while the engine is serialized.
    @(negedge _clk);
    _req = '{
        valid: 1'b1,
        ctrl: '{en: 1'b1, op: AMO_OP_SWAP, aq: 1'b1, rl: 1'b1},
        address: virtual_address_u'(32'hffff_0000),
        operand: 32'hdead_beef,
        ctx: '0
    };
    check(!_req_ready, "younger AMO refused while executor active");
    tick();
    check(_memory_if.req === stalled_request, "younger AMO does not replace active request");
    _req.valid = 1'b0;

    repeat (2) begin
      tick();
      check(_memory_if.req === stalled_request, "read request stable under backpressure");
    end
    accept_memory_request();
    check(!_memory_if.req.valid, "read request removed after acceptance");

    send_memory_response(32'h0000_0010, MMU_FAULT_NONE, address.raw);
    check(_memory_if.req.valid, "write request asserted after read response");
    check(_memory_if.req.write_en, "second request is a write");
    check(_memory_if.req.addr == address.raw, "write request preserves address");
    check(_memory_if.req.write_data == 32'h0000_0017, "write contains AMO result");
    check(_memory_if.req.write_mask == '1, "write enables every byte");
    stalled_request = _memory_if.req;
    repeat (2) begin
      tick();
      check(_memory_if.req === stalled_request, "write request stable under backpressure");
    end
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, address.raw);

    check(_rsp.valid, "AMO response asserted after write response");
    check(_rsp.result == 32'h0000_0010, "AMO returns old memory value");
    check(_rsp.fault == MMU_FAULT_NONE, "successful AMO has no fault");
    repeat (2) begin
      tick();
      check(_rsp.valid && _rsp.result == 32'h0000_0010,
            "AMO response stable under backpressure");
    end
    _rsp_ready = 1'b1;
    tick();
    _rsp_ready = 1'b0;
    check(!_rsp.valid, "AMO response clears after acceptance");
    check(_req_ready, "executor returns to idle after response acceptance");

    address.raw = 32'h8765_4000;
    start_request(AMO_OP_SWAP, address, 32'hdead_beef);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_PAGE, '0);
    check(_rsp.valid, "read fault produces an AMO response");
    check(_rsp.fault == MMU_FAULT_PAGE, "read fault is preserved");
    check(!_memory_if.req.valid, "read fault suppresses write request");
    _rsp_ready = 1'b1;
    tick();
    _rsp_ready = 1'b0;

    // LR returns the loaded value and establishes a physical-word reservation
    // without issuing a write.
    address.raw = 32'h1000_0000;
    start_request(AMO_OP_LR, address, '0);
    accept_memory_request();
    send_memory_response(32'hcafe_babe, MMU_FAULT_NONE, 32'h2000_0000);
    check(!_memory_if.req.valid, "LR does not issue a write request");
    consume_amo_response(32'hcafe_babe, MMU_FAULT_NONE, "LR");

    // SC succeeds when its translated physical word matches the reservation.
    start_request(AMO_OP_SC, address, 32'hdead_beef);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h2000_0000);
    check(_memory_if.req.valid && _memory_if.req.write_en,
          "matching SC issues a write request");
    check(_memory_if.req.write_data == 32'hdead_beef, "SC writes rs2 operand");
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h2000_0000);
    consume_amo_response('0, MMU_FAULT_NONE, "successful SC");

    // The successful attempt consumed the reservation, so another SC fails
    // without issuing a write.
    start_request(AMO_OP_SC, address, 32'h0123_4567);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h2000_0000);
    check(!_memory_if.req.valid, "SC without reservation suppresses write");
    consume_amo_response(32'd1, MMU_FAULT_NONE, "SC without reservation");

    // Architectural events such as a trap, SFENCE.VMA, or SATP write arrive
    // through reservation_clear and invalidate an otherwise matching LR.
    start_request(AMO_OP_LR, address, '0);
    accept_memory_request();
    send_memory_response(32'haaaa_5555, MMU_FAULT_NONE, 32'h2000_0000);
    consume_amo_response(32'haaaa_5555, MMU_FAULT_NONE, "LR before external clear");
    _reservation_clear = 1'b1;
    tick();
    _reservation_clear = 1'b0;
    start_request(AMO_OP_SC, address, 32'h0123_4567);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h2000_0000);
    check(!_memory_if.req.valid, "external clear makes matching SC suppress write");
    consume_amo_response(32'd1, MMU_FAULT_NONE, "SC after external clear");

    // Matching uses the translated physical word, not the virtual address.
    start_request(AMO_OP_LR, address, '0);
    accept_memory_request();
    send_memory_response(32'h1111_2222, MMU_FAULT_NONE, 32'h2000_0000);
    consume_amo_response(32'h1111_2222, MMU_FAULT_NONE, "second LR");
    address.raw = 32'h3000_0000;
    start_request(AMO_OP_SC, address, 32'h3333_4444);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h2000_0004);
    check(!_memory_if.req.valid, "mismatched physical SC suppresses write");
    consume_amo_response(32'd1, MMU_FAULT_NONE, "mismatched SC");

    // A faulting SC propagates the fault and consumes the reservation.
    address.raw = 32'h4000_0000;
    start_request(AMO_OP_LR, address, '0);
    accept_memory_request();
    send_memory_response(32'h5555_6666, MMU_FAULT_NONE, 32'h5000_0000);
    consume_amo_response(32'h5555_6666, MMU_FAULT_NONE, "LR before faulting SC");
    start_request(AMO_OP_SC, address, 32'h7777_8888);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_PAGE, '0);
    check(!_memory_if.req.valid, "faulting SC suppresses write");
    consume_amo_response('0, MMU_FAULT_PAGE, "faulting SC");
    start_request(AMO_OP_SC, address, 32'h9999_aaaa);
    accept_memory_request();
    send_memory_response('0, MMU_FAULT_NONE, 32'h5000_0000);
    check(!_memory_if.req.valid, "SC after fault has no reservation");
    consume_amo_response(32'd1, MMU_FAULT_NONE, "SC after fault");

    if (_errors == 0) begin
      $display("tb_amo_execute: PASS (%0d checks)", _checks);
      $finish;
    end else begin
      $fatal(1, "tb_amo_execute: FAIL (%0d failures out of %0d checks)", _errors, _checks);
    end
  end

  initial begin
    #(TimeoutNs);
    $fatal(1, "tb_amo_execute: TIMEOUT after %0d ns", TimeoutNs);
  end

endmodule
