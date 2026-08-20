`timescale 1ns / 1ps

module tb_mem_arbiter;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;

  logic _clk;
  logic _rst;
  int   _errors;
  int   _checks;

  mem_if _ifetch (
    _clk,
    _rst
  );
  mem_if _data (
    _clk,
    _rst
  );
  mem_if _mem (
    _clk,
    _rst
  );

  // This testbench drives the master side. Response acceptance is controllable
  // so the arbiter's `rsp_ready` fan-out can be exercised.
  logic _ifetch_rsp_ready;
  logic _data_rsp_ready;
  assign _ifetch.rsp_ready = _ifetch_rsp_ready;
  assign _data.rsp_ready   = _data_rsp_ready;


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

  initial begin
    _clk = 1'b0;
    _rst = 1'b1;
    _errors = 0;
    _checks = 0;
    clear_requests();
    clear_memory_response();
    _mem.req_ready = 1'b1;  // slave accepts on the presented cycle by default
    _ifetch_rsp_ready = 1'b1;
    _data_rsp_ready = 1'b1;

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_mem_arbiter.vcd");
      $dumpvars(0, tb_mem_arbiter);
    end

    repeat (2) @(posedge _clk);
    _rst = 1'b0;
    #1;

    // Combinational slaves may accept and answer in the same cycle, which
    // leaves the arbiter idle rather than owing a response.
    _data.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h1000_0000, default: '0};
    _mem.rsp  = '{valid: 1'b1, read_data: 32'hcafe_babe};
    #1;
    expect_bit(_mem.req.valid, 1'b1, "same-cycle data request forwarded");
    expect_bit(_data.req_ready, 1'b1, "same-cycle data request accepted");
    expect_bit(_data.rsp.valid, 1'b1, "same-cycle data response routed");
    expect_word(_data.rsp.read_data, 32'hcafe_babe, "same-cycle data response payload");
    expect_bit(_ifetch.rsp.valid, 1'b0, "same-cycle data response excludes fetch");
    expect_bit(_ifetch.req_ready, 1'b0, "idle port is not accepted");
    @(posedge _clk);
    #1;
    clear_requests();
    clear_memory_response();

    // A slave that refuses holds the whole transaction: the request stays
    // presented, nobody is accepted, and the arbiter does not advance. This is
    // the case the interface previously had no way to express -- the request
    // would simply have been dropped.
    _ifetch.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0080, default: '0};
    _mem.req_ready = 1'b0;
    #1;
    expect_bit(_mem.req.valid, 1'b1, "refused request is still presented");
    expect_bit(_ifetch.req_ready, 1'b0, "refused request is not accepted");
    repeat (3) begin
      @(posedge _clk);
      #1;
      expect_bit(_mem.req.valid, 1'b1, "refused request stays presented across cycles");
      expect_bit(_ifetch.req_ready, 1'b0, "refused request stays unaccepted");
    end
    _mem.req_ready = 1'b1;
    #1;
    expect_bit(_ifetch.req_ready, 1'b1, "request is accepted once the slave is ready");
    @(posedge _clk);
    #1;
    clear_requests();
    expect_bit(_mem.req.valid, 1'b0, "accepted request is not re-presented");
    _mem.rsp.valid = 1'b1;
    _mem.rsp.read_data = 32'h0050_0093;
    #1;
    expect_bit(_ifetch.rsp.valid, 1'b1, "delayed response routed to the accepted port");
    @(posedge _clk);
    #1;
    clear_memory_response();
    #1;

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
    expect_bit(_ifetch.rsp.valid, 1'b0, "fetch waits for response");

    _mem.rsp.valid = 1'b1;
    _mem.rsp.read_data = 32'h0050_0093;
    #1;
    expect_bit(_ifetch.rsp.valid, 1'b1, "fetch response routed");
    expect_word(_ifetch.rsp.read_data, 32'h0050_0093, "fetch response data");
    expect_bit(_data.rsp.valid, 1'b0, "fetch response excluded from data");
    @(posedge _clk);
    #1;
    clear_memory_response();
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
    _mem.rsp.valid = 1'b1;
    #1;
    expect_bit(_data.rsp.valid, 1'b1, "data completion routed");
    expect_bit(_ifetch.rsp.valid, 1'b0, "data completion excluded from fetch");
    @(posedge _clk);
    #1;
    clear_memory_response();
    #1;

    // Simultaneous requests select data and remember that same owner. The
    // losing port keeps its request presented -- a master may not withdraw one
    // that has not been accepted.
    _ifetch.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0300, default: '0};
    _data.req   = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0400, default: '0};
    #1;
    expect_word(_mem.req.addr, 32'h0000_0400, "simultaneous requests give data priority");
    expect_bit(_data.req_ready, 1'b1, "the winner is the port that is accepted");
    expect_bit(_ifetch.req_ready, 1'b0, "the loser is not accepted");
    @(posedge _clk);
    #1;
    _data.req = '0;

    // The still-pending fetch cannot replace the recorded owner while busy.
    #1;
    expect_bit(_mem.req.valid, 1'b0, "pending request suppressed while busy");
    expect_bit(_ifetch.req_ready, 1'b0, "pending request not accepted while busy");
    _mem.rsp.valid = 1'b1;
    _mem.rsp.read_data = 32'h1234_5678;
    #1;
    expect_bit(_data.rsp.valid, 1'b1, "simultaneous winner owns response");
    expect_word(_data.rsp.read_data, 32'h1234_5678, "data read response");
    expect_bit(_ifetch.rsp.valid, 1'b0, "busy fetch cannot steal response");
    @(posedge _clk);
    #1;
    clear_memory_response();
    #1;

    // With the bus free, the fetch that waited is granted.
    expect_bit(_mem.req.valid, 1'b1, "held fetch is granted once the bus frees");
    expect_word(_mem.req.addr, 32'h0000_0300, "held fetch keeps its address");
    expect_bit(_ifetch.req_ready, 1'b1, "held fetch is accepted");
    @(posedge _clk);
    #1;
    clear_requests();
    _mem.rsp.valid = 1'b1;
    #1;
    @(posedge _clk);
    #1;
    clear_memory_response();
    #1;

    // A master that refuses its response holds the whole transaction. The
    // arbiter must pass that refusal down to the slave rather than swallowing
    // it, and must not free itself until the response is actually taken.
    _ifetch.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0700, default: '0};
    #1;
    @(posedge _clk);
    #1;
    clear_requests();
    _ifetch_rsp_ready = 1'b0;
    _mem.rsp.valid = 1'b1;
    _mem.rsp.read_data = 32'h0bad_c0de;
    #1;
    expect_bit(_mem.rsp_ready, 1'b0, "refusal is passed down to the slave");
    expect_bit(_ifetch.rsp.valid, 1'b1, "refused response is still offered to its owner");
    repeat (3) begin
      @(posedge _clk);
      #1;
      expect_bit(_mem.rsp_ready, 1'b0, "refusal holds across cycles");
      expect_bit(_mem.req.valid, 1'b0, "arbiter stays busy while the response is untaken");
    end
    _ifetch_rsp_ready = 1'b1;
    #1;
    expect_bit(_mem.rsp_ready, 1'b1, "acceptance is passed down to the slave");
    @(posedge _clk);
    #1;
    clear_memory_response();
    #1;
    expect_bit(_data.rsp_ready, 1'b1, "the idle port's acceptance is its own");

    // Reset cancels an outstanding transaction and removes its response owner.
    _data.req = '{valid: 1'b1, write_en: 1'b0, addr: 32'h0000_0600, default: '0};
    #1;
    @(posedge _clk);
    #1;
    clear_requests();
    _rst = 1'b1;
    @(posedge _clk);
    #1;
    _mem.rsp.valid = 1'b1;
    _mem.rsp.read_data = 32'hffff_ffff;
    #1;
    expect_bit(_ifetch.rsp.valid, 1'b0, "reset clears fetch owner");
    expect_bit(_data.rsp.valid, 1'b0, "reset clears data owner");
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
