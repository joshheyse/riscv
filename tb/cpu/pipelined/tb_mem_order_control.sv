`timescale 1ns / 1ps

module tb_mem_order_control
  import riscv_pkg::*;
  import pipelined_pkg::*;
();

  localparam int unsigned TimeoutNs = 10_000;

  logic           clk;
  logic           rst = 1'b1;
  ex_mem_t        ex_mem;
  logic           dbus_wait;
  logic           trap_in_flight;
  logic           busy;
  logic           start;
  redirect_t      redirect;
  tlb_flush_req_t tlb_flush;
  tlb_flush_req_t expected_tlb_flush;

  int unsigned    errors = 0;
  int unsigned    checks = 0;

  cache_command_if dcache_command ();
  cache_command_if icache_command ();

  initial begin
    clk = 1'b0;
    forever begin
      #5 clk = ~clk;
    end
  end

  mem_order_control _dut (
    .clk(clk),
    .rst(rst),
    .ex_mem(ex_mem),
    .dbus_wait(dbus_wait),
    .trap_in_flight(trap_in_flight),
    .busy(busy),
    .start(start),
    .redirect(redirect),
    .tlb_flush(tlb_flush),
    .dcache_command(dcache_command),
    .icache_command(icache_command)
  );

  task automatic check(input logic condition, input string what);
    checks++;
    if (!condition) begin
      errors++;
      $error("FAIL: %s", what);
    end
  endtask

  task automatic reset_dut;
    rst = 1'b1;
    ex_mem = '0;
    dbus_wait = 1'b0;
    trap_in_flight = 1'b0;
    dcache_command.ready = 1'b0;
    dcache_command.done_valid = 1'b0;
    icache_command.ready = 1'b0;
    icache_command.done_valid = 1'b0;
    repeat (2) begin
      @(posedge clk);
    end
    rst = 1'b0;
    @(negedge clk);
  endtask

  task automatic present_fence_i(input pc_t fence_pc);
    ex_mem = '0;
    ex_mem.valid = 1'b1;
    ex_mem.pc = fence_pc;
    ex_mem.ctrl.mem_order = MEM_ORDER_FENCE_I;
  endtask

  task automatic present_sfence_vma(input pc_t fence_pc, input tlb_flush_req_t flush_req);
    ex_mem = '0;
    ex_mem.valid = 1'b1;
    ex_mem.pc = fence_pc;
    ex_mem.ctrl.mem_order = MEM_ORDER_SFENCE_VMA;
    ex_mem.tlb_flush = flush_req;
  endtask

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_mem_order_control);
    end

    reset_dut();

    // FENCE and ordinary instructions do not start the FENCE.I sequence.
    ex_mem.valid = 1'b1;
    ex_mem.ctrl.mem_order = MEM_ORDER_FENCE;
    #1;
    check(!start && !busy, "plain FENCE does not run cache maintenance");
    ex_mem.ctrl.mem_order = MEM_ORDER_NONE;
    #1;
    check(!start && !busy, "ordinary instruction does not run cache maintenance");

    present_fence_i(32'h0000_0080);
    #1;
    check(start && !tlb_flush.valid, "FENCE.I starts maintenance without flushing the TLB");
    reset_dut();

    // An older trap, a trap attached to SFENCE.VMA itself, or an unfinished data
    // access must prevent acceptance. Keeping EX/MEM valid verifies that the
    // request is accepted only after the blocker has cleared.
    expected_tlb_flush = '{
        valid: 1'b1,
        all_vpns: 1'b0,
        vpn: sv32_vpn_t'(20'h12345),
        all_asids: 1'b0,
        asid: sv32_asid_t'(9'h012)
    };
    present_sfence_vma(32'h0000_0100, expected_tlb_flush);
    trap_in_flight = 1'b1;
    repeat (2) begin
      @(negedge clk);
      check(!start && !dcache_command.valid,
            "trap in flight has priority over SFENCE.VMA acceptance");
    end
    trap_in_flight = 1'b0;
    dbus_wait = 1'b1;
    #1;
    check(!start, "data-bus wait prevents SFENCE.VMA acceptance");
    dbus_wait = 1'b0;
    ex_mem.trap.valid = 1'b1;
    #1;
    check(!start, "trapping SFENCE.VMA is not accepted");
    ex_mem.trap.valid = 1'b0;
    #1;
    check(start, "unblocked SFENCE.VMA requests pipeline serialization");

    @(posedge clk);
    #1;
    ex_mem = '0;
    @(negedge clk);
    check(busy, "sequencer is busy while requesting D-cache maintenance");
    check(dcache_command.valid, "D-cache command remains valid until accepted");
    check(dcache_command.op.clean && !dcache_command.op.invalidate,
          "D-cache command is clean only");
    check(!icache_command.valid, "I-cache command waits for D-cache completion");

    repeat (2) begin
      @(posedge clk);
      @(negedge clk);
      check(dcache_command.valid, "D-cache command tolerates requester backpressure");
    end

    dcache_command.ready = 1'b1;
    @(posedge clk);
    #1;
    dcache_command.ready = 1'b0;
    @(negedge clk);
    check(busy && dcache_command.done_ready,
          "sequencer waits for D-cache completion after command acceptance");
    check(!icache_command.valid, "I-cache command is not issued before D-cache done");

    repeat (2) begin
      @(posedge clk);
      @(negedge clk);
      check(dcache_command.done_ready, "D-cache completion channel tolerates latency");
    end

    dcache_command.done_valid = 1'b1;
    @(posedge clk);
    #1;
    dcache_command.done_valid = 1'b0;
    @(negedge clk);
    check(busy && icache_command.valid, "I-cache command follows completed D-cache clean");
    check(!icache_command.op.clean && icache_command.op.invalidate,
          "I-cache command is invalidate only");

    icache_command.ready = 1'b1;
    @(posedge clk);
    #1;
    icache_command.ready = 1'b0;
    @(negedge clk);
    check(busy && icache_command.done_ready,
          "sequencer waits for I-cache completion after command acceptance");

    icache_command.done_valid = 1'b1;
    @(posedge clk);
    #1;
    icache_command.done_valid = 1'b0;
    @(negedge clk);
    check(!busy && redirect.valid, "completed SFENCE.VMA redirects without remaining busy");
    check(redirect.pc == 32'h0000_0104, "SFENCE.VMA resumes at the following instruction");
    check(tlb_flush == expected_tlb_flush, "SFENCE.VMA flushes its latched VPN and ASID selectors");

    @(posedge clk);
    @(negedge clk);
    check(!redirect.valid && !busy && !tlb_flush.valid,
          "completion redirect and TLB flush are single-cycle pulses");

    if (errors == 0) begin
      $display("tb_mem_order_control: PASS (%0d checks)", checks);
      $finish;
    end else begin
      $display("tb_mem_order_control: FAIL (%0d failures out of %0d checks)", errors, checks);
      $fatal(1);
    end
  end

  initial begin
    #(TimeoutNs);
    $display("tb_mem_order_control: TIMEOUT after %0d ns", TimeoutNs);
    $fatal(1);
  end

endmodule
