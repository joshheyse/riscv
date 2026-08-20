`timescale 1ns / 1ps

module led_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   LedAddr = 32'h10000000,
  parameter int unsigned NumLeds = 1
) (
  input logic clk,
  input logic rst,

  output logic [NumLeds-1:0] led,
  output logic               selected,

  mem_if.slave mem
);


  // This slave can always take a request on the cycle it is presented, so
  // acceptance is unconditional. Drive it for real only if that changes.
  assign mem.req_ready = 1'b1;

  localparam int unsigned WordBits = $bits(mem_addr_t);
  initial begin
    assert (NumLeds < WordBits);
  end

  assign selected = (mem.req.addr == LedAddr);
  assign mem.rsp.valid = mem.req.valid && selected;

  always_comb begin
    mem.rsp.read_data = '0;
    mem.rsp.read_data = {{(WordBits - NumLeds) {1'b0}}, led};
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      led <= '0;
    end else if (mem.req.write_en && selected) begin
      led <= mem.req.write_data[NumLeds-1:0];
    end
  end

endmodule
