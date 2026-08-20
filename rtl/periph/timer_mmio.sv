`timescale 1ns / 1ps

module timer_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t TimerLoAddr = 32'h10002000,
  parameter mem_addr_t TimerHiAddr = 32'h10002004
) (
  input logic clk,
  input logic rst,

  output logic selected,

  mem_if.slave mem
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  initial begin
    assert (TimerLoAddr != TimerHiAddr);
  end

  dword_t _counter;
  assign selected = (mem.req.addr == TimerLoAddr || mem.req.addr == TimerHiAddr);
  assign mem.rsp.valid = mem.req.valid && selected;

  always_comb begin
    mem.rsp.read_data = '0;
    if (!selected) begin
      mem.rsp.read_data = '0;
    end else if (mem.req.addr == TimerLoAddr) begin
      mem.rsp.read_data = _counter[31:0];
    end else begin
      mem.rsp.read_data = _counter[63:32];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _counter <= '0;
    end else begin
      _counter <= _counter + 1;
    end
  end

endmodule
