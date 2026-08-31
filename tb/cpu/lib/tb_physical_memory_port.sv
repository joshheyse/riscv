`timescale 1ns / 1ps

module tb_physical_memory_port;
  import riscv_pkg::*;

  localparam time ClkPeriod = 10ns;

  logic _clk;
  logic _rst;
  int   _checks;
  int   _errors;

  mem_if _upstream (
    _clk,
    _rst
  );
  mem_if _downstream (
    _clk,
    _rst
  );

  physical_memory_port _dut (
    .clk(_clk),
    .rst(_rst),
    .upstream(_upstream),
    .downstream(_downstream)
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

  initial begin
    _clk = 1'b0;
    _rst = 1'b1;
    _checks = 0;
    _errors = 0;
    _upstream.req = '0;
    _upstream.rsp_ready = 1'b1;
    _downstream.req_ready = 1'b0;
    _downstream.rsp = '0;

    if ($test$plusargs("trace")) begin
      $dumpfile("tb_physical_memory_port.vcd");
      $dumpvars(0, tb_physical_memory_port);
    end

    repeat (2) @(posedge _clk);
    _rst = 1'b0;
    #1;

    // The boundary accepts upstream first; the request cannot pass through
    // combinationally to physical memory.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b1,
        addr: 32'h1000_0040,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_STORE,
        privilege: PRIV_MACHINE,
        write_data: 32'hdead_beef,
        write_mask: 4'b1010
    };
    #1;
    expect_bit(_upstream.req_ready, 1'b1, "idle port accepts request");
    expect_bit(_downstream.req.valid, 1'b0, "request does not pass through combinationally");
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_upstream.req_ready, 1'b0, "port blocks a second outstanding request");
    expect_bit(_downstream.req.valid, 1'b1, "captured request presented downstream");
    expect_word(_downstream.req.addr, 32'h1000_0040, "request address retained");
    expect_word(_downstream.req.write_data, 32'hdead_beef, "request data retained");
    expect_bit(_downstream.req.write_mask == 4'b1010, 1'b1, "request mask retained");

    // Backpressure must leave the registered downstream request stable.
    repeat (2) begin
      @(posedge _clk);
      #1;
      expect_bit(_downstream.req.valid, 1'b1, "request held while downstream stalls");
      expect_word(_downstream.req.addr, 32'h1000_0040, "stalled request remains stable");
    end

    // Even a same-cycle physical response is captured, not exposed directly.
    _downstream.req_ready = 1'b1;
    _downstream.rsp = '{
        valid: 1'b1,
        read_data: 32'hcafe_babe,
        fault: MMU_FAULT_NONE,
        pmp_annotation: '0
    };
    #1;
    expect_bit(_upstream.rsp.valid, 1'b0, "same-cycle response does not pass through");
    @(posedge _clk);
    #1;
    _downstream.rsp = '0;
    expect_bit(_upstream.rsp.valid, 1'b1, "captured response presented upstream");
    expect_word(_upstream.rsp.read_data, 32'hcafe_babe, "response data retained");
    @(posedge _clk);
    #1;
    expect_bit(_upstream.req_ready, 1'b1, "port returns idle after response transfer");

    // Exercise a delayed response and upstream response backpressure.
    _upstream.req = '{
        valid: 1'b1,
        write_en: 1'b0,
        addr: 32'h8000_0100,
        size: MEM_SIZE_WORD,
        access: MMU_ACCESS_LOAD,
        privilege: PRIV_MACHINE,
        write_data: '0,
        write_mask: '0
    };
    @(posedge _clk);
    #1;
    _upstream.req = '0;
    expect_bit(_downstream.req.valid, 1'b1, "second request presented downstream");
    @(posedge _clk);
    #1;
    expect_bit(_downstream.req.valid, 1'b0, "accepted request removed while awaiting response");
    expect_bit(_downstream.rsp_ready, 1'b1, "port ready for delayed response");
    _upstream.rsp_ready = 1'b0;
    _downstream.rsp = '{
        valid: 1'b1,
        read_data: 32'h0123_4567,
        fault: MMU_FAULT_NONE,
        pmp_annotation: '0
    };
    @(posedge _clk);
    #1;
    _downstream.rsp = '0;
    expect_bit(_upstream.rsp.valid, 1'b1, "delayed response presented upstream");
    expect_word(_upstream.rsp.read_data, 32'h0123_4567, "delayed response data retained");
    repeat (2) begin
      @(posedge _clk);
      #1;
      expect_bit(_upstream.rsp.valid, 1'b1, "response held under upstream backpressure");
      expect_word(_upstream.rsp.read_data, 32'h0123_4567, "stalled response remains stable");
    end
    _upstream.rsp_ready = 1'b1;
    @(posedge _clk);
    #1;
    expect_bit(_upstream.rsp.valid, 1'b0, "response withdrawn after acceptance");
    expect_bit(_upstream.req_ready, 1'b1, "port ready for next transaction");

    $display("tb_physical_memory_port: %0d checks, %0d errors", _checks, _errors);
    if (_errors != 0) begin
      $fatal(1, "tb_physical_memory_port failed");
    end
    $finish;
  end

  initial begin
    #(ClkPeriod * 100);
    $fatal(1, "tb_physical_memory_port timed out");
  end

endmodule
