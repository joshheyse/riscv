`timescale 1ns / 1ps

module led_mmio #(
  parameter riscv_pkg::word_t LedAddr = memmap_pkg::LedAddr,
  parameter int unsigned NumLeds = 8
) (
  input logic clk,
  input logic rst,

  input logic mem_write,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,
  output logic [NumLeds-1:0] led
);

  localparam int unsigned WordBits = 32;
  initial begin
    assert (NumLeds < WordBits);
  end

  assign selected  = (mem_addr == LedAddr);

  assign read_data = {{(WordBits - NumLeds) {1'b0}}, led};

  always_ff @(posedge clk) begin
    if (rst) begin
      led <= '0;
    end else if (mem_write && selected) begin
      led <= mem_write_data[NumLeds-1:0];
    end
  end

  logic unused_write_data;
  assign unused_write_data = |mem_write_data[WordBits-1:NumLeds];

endmodule
