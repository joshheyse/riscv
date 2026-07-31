`timescale 1ns / 1ps

module gpio_mmio #(
  parameter logic [31:0] GpioDataInAddr = '0,
  parameter logic [31:0] GpioDataOutAddr = '0,
  parameter logic [31:0] GpioDirAddr = '0,
  parameter logic [31:0] GpioSetAddr = '0,
  parameter logic [31:0] GpioClearAddr = '0,
  parameter logic [31:0] GpioToggleAddr = '0,
  parameter int unsigned NumGpio = 1
) (
  input logic clk,
  input logic rst,

  input logic mem_write,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe
);

  localparam int unsigned WordBits = $bits(mem_addr);
  initial begin
    assert (NumGpio < WordBits);
  end

  logic [NumGpio-1:0] read;


  assign selected = mem_addr == GpioDataInAddr || mem_addr == GpioDataOutAddr || mem_addr == GpioDirAddr ||
             mem_addr == GpioSetAddr || mem_addr == GpioClearAddr || mem_addr == GpioToggleAddr;

  always_ff @(posedge clk) begin
    if (rst) begin
      gpio_out <= 0;
      gpio_oe  <= 0;
    end else begin
      if (mem_write && selected) begin
        if (mem_addr == GpioDataOutAddr) begin
          gpio_out <= mem_write_data[NumGpio-1:0];
        end else if (mem_addr == GpioDirAddr) begin
          gpio_oe <= mem_write_data[NumGpio-1:0];
        end else if (mem_addr == GpioSetAddr) begin
          gpio_out <= gpio_out | mem_write_data[NumGpio-1:0];
        end else if (mem_addr == GpioClearAddr) begin
          gpio_out <= gpio_out & ~mem_write_data[NumGpio-1:0];
        end else if (mem_addr == GpioToggleAddr) begin
          gpio_out <= gpio_out ^ mem_write_data[NumGpio-1:0];
        end
      end
    end
  end

  assign read = mem_addr == GpioDataInAddr ? gpio_in :
                   mem_addr == GpioDataOutAddr ? gpio_out :
                   mem_addr == GpioDirAddr ? gpio_oe :
                   8'h0;

  assign read_data = {{WordBits - NumGpio{1'b0}}, read};

  logic unused_write_data;
  assign unused_write_data = |mem_write_data[WordBits-1:NumGpio];

endmodule
