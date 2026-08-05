`timescale 1ns / 1ps

module led_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   LedAddr = '0,
  parameter int unsigned NumLeds = 1
) (
  input logic clk,
  input logic rst,

  input  logic                          mem_valid,
  input  logic                          mem_write_en,
  input  mem_addr_t                     mem_addr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  mem_data_t                     mem_write_data,
  input  mem_write_mask_t               mem_write_mask,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic                          selected,
  output logic                          mem_ready,
  output mem_data_t                     mem_read_data,
  output logic            [NumLeds-1:0] led
);

  localparam int unsigned WordBits = $bits(mem_addr);
  initial begin
    assert (NumLeds < WordBits);
  end

  assign selected = (mem_addr == LedAddr);
  assign mem_ready = mem_valid && selected;

  assign mem_read_data = {{(WordBits - NumLeds) {1'b0}}, led};

  always_ff @(posedge clk) begin
    if (rst) begin
      led <= '0;
    end else if (mem_write_en && selected) begin
      led <= mem_write_data[NumLeds-1:0];
    end
  end

endmodule
