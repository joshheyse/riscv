`timescale 1ns / 1ps

module tb_mem_arbiter;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;

  logic _clk;
  logic _rst;
  int   _errors;
  int   _checks;

  mem_if _ifetch ();
  mem_if _data ();
  mem_if _mem ();

  mem_arbiter _dut (
    .clk(_clk),
    .rst(_rst),
    .ifetch(_ifetch),
    .data(_data),
    .mem(_mem)
  );

  always #(ClkPeriod / 2) _clk = ~_clk;

  task automatic expect_bit(input logic actual, input logic expected, input string what);
    _checks++;
    if (actual !== expected) begin
      $error("%s: expected %b, got %b", what, expected, actual);
      _errors++;
    end
  endtask

  task automatic expect_word(input word_t actual, input word_t expected, input string what);
    _checks++;
    if (actual !== expected) begin
      $error("%s: expected 0x%08h, got 0x%08h", what, expected, actual);
      _errors++;
    end
  endtask

  task automatic clear_requests;
    _ifetch.req = '0;
    _data.req   = '0;
  endtask

  task automatic clear_memory_response;
    _mem.rsp = '0;
  endtask

  task automatic complete_response(input word_t read_data);
    _mem.rsp.ready = 1'b1;
    _mem.rsp.read_data = read_data;
    #1;
    @(posedge _clk);
    #1;
    clear_memory_response();
  endtask

  initial begin
    _clk = 1'b0;
    _rst = 1'b1;
    _errors = 0;
    _checks = 0;
    clear_requests();
    clear_memory_response();

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_mem_arbiter.vcd");
      $dumpvars(0, tb_mem_arbiter);
    end

    repeat (2) @(posedge _clk);
    _rst = 1'b0;
    #1;

    // Combinational slaves may complete in the request cycle without putting
    // the arbiter into its delayed-response state.
    _data.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h1000_0000, default: '0};
    _mem.rsp  = '{ready: 1'b1, read_data: 32'hcafe_babe};
    #1;
    expect_bit(_mem.req.valid, 1'b1, "same-cycle data request forwarded");
    expect_bit(_data.rsp.ready, 1'b1, "same-cycle data response routed");
    expect_word(_data.rsp.read_data, 32'hcafe_babe, "same-cycle data response payload");
    expect_bit(_ifetch.rsp.ready, 1'b0, "same-cycle data response excludes fetch");
    @(posedge _clk);
    #1;
    clear_requests();
    clear_memory_response();

    // An instruction request is forwarded as a read even if its unused write
    // fields are accidentally nonzero.
    _ifetch.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: 32'h0000_0100,
        write_data: 32'hdead_beef,
        write_mask: 4'b1111
    };
    #1;
    expect_bit(_mem.req.valid, 1'b1, "fetch request forwarded");
    expect_bit(_mem.req.write_en, 1'b0, "fetch forced read-only");
    expect_word(_mem.req.addr, 32'h0000_0100, "fetch address");
    expect_word(_mem.req.write_data, '0, "fetch write data cleared");
    expect_bit(|_mem.req.write_mask, 1'b0, "fetch write mask cleared");

    @(posedge _clk);
    #1;
    clear_requests();
    expect_bit(_mem.req.valid, 1'b0, "no repeated fetch request while busy");
    expect_bit(_ifetch.rsp.ready, 1'b0, "fetch waits for response");

    _mem.rsp.ready = 1'b1;
    _mem.rsp.read_data = 32'h0050_0093;
    #1;
    expect_bit(_ifetch.rsp.ready, 1'b1, "fetch response routed");
    expect_word(_ifetch.rsp.read_data, 32'h0050_0093, "fetch response data");
    expect_bit(_data.rsp.ready, 1'b0, "fetch response excluded from data");
    @(posedge _clk);
    #1;
    clear_memory_response();
    @(posedge _clk);  // drain a delayed slave's retired response
    #1;

    // Data stores forward every request field unchanged.
    _data.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: 32'h0000_0202,
        write_data: 32'haabb_ccdd,
        write_mask: 4'b1100
    };
    #1;
    expect_bit(_mem.req.valid, 1'b1, "data store forwarded");
    expect_bit(_mem.req.write_en, 1'b1, "data store write enable");
    expect_word(_mem.req.addr, 32'h0000_0202, "data store address");
    expect_word(_mem.req.write_data, 32'haabb_ccdd, "data store payload");
    expect_bit(_mem.req.write_mask == 4'b1100, 1'b1, "data store mask");

    @(posedge _clk);
    #1;
    clear_requests();
    expect_bit(_mem.req.valid, 1'b0, "no repeated data store while busy");
    _mem.rsp.ready = 1'b1;
    #1;
    expect_bit(_data.rsp.ready, 1'b1, "data completion routed");
    expect_bit(_ifetch.rsp.ready, 1'b0, "data completion excluded from fetch");
    @(posedge _clk);
    #1;
    clear_memory_response();
    @(posedge _clk);  // drain a delayed slave's retired response
    #1;

    // Simultaneous requests select data and remember that same owner.
    _ifetch.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0300, default: '0};
    _data.req   = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0400, default: '0};
    #1;
    expect_word(_mem.req.addr, 32'h0000_0400, "simultaneous requests give data priority");
    @(posedge _clk);
    #1;
    clear_requests();

    // A new request cannot replace the recorded owner while busy.
    _ifetch.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0500, default: '0};
    #1;
    expect_bit(_mem.req.valid, 1'b0, "new request suppressed while busy");
    _mem.rsp.ready = 1'b1;
    _mem.rsp.read_data = 32'h1234_5678;
    #1;
    expect_bit(_data.rsp.ready, 1'b1, "simultaneous winner owns response");
    expect_word(_data.rsp.read_data, 32'h1234_5678, "data read response");
    expect_bit(_ifetch.rsp.ready, 1'b0, "busy fetch cannot steal response");
    @(posedge _clk);
    #1;
    clear_requests();
    clear_memory_response();
    @(posedge _clk);  // drain a delayed slave's retired response
    #1;

    // Reset cancels an outstanding transaction and removes its response owner.
    _data.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0600, default: '0};
    #1;
    @(posedge _clk);
    #1;
    clear_requests();
    _rst = 1'b1;
    @(posedge _clk);
    #1;
    _mem.rsp.ready = 1'b1;
    _mem.rsp.read_data = 32'hffff_ffff;
    #1;
    expect_bit(_ifetch.rsp.ready, 1'b0, "reset clears fetch owner");
    expect_bit(_data.rsp.ready, 1'b0, "reset clears data owner");
    expect_bit(_mem.req.valid, 1'b0, "reset leaves no request active");
    _rst = 1'b0;
    clear_memory_response();

    if (_errors == 0) begin
      $display("tb_mem_arbiter: PASS (%0d checks)", _checks);
    end else begin
      $display("tb_mem_arbiter: FAIL (%0d errors)", _errors);
      $fatal(1);
    end
    $finish;
  end

  initial begin
    #10us;
    $fatal(1, "tb_mem_arbiter: watchdog timeout");
  end

endmodule
