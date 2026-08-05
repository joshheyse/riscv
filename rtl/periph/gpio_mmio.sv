`timescale 1ns / 1ps

module gpio_mmio
  import riscv_pkg::*;
#(
  parameter logic        [31:0] GpioDataInAddr  = '0,
  parameter logic        [31:0] GpioDataOutAddr = '0,
  parameter logic        [31:0] GpioDirAddr     = '0,
  parameter logic        [31:0] GpioSetAddr     = '0,
  parameter logic        [31:0] GpioClearAddr   = '0,
  parameter logic        [31:0] GpioToggleAddr  = '0,
  parameter int unsigned        NumGpio         = 1
) (
  input logic clk,
  input logic rst,

  input  logic            mem_valid,
  input  logic            mem_write_en,
  input  mem_addr_t       mem_addr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  mem_data_t       mem_write_data,
  input  mem_write_mask_t mem_write_mask,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic            selected,
  output logic            mem_ready,
  output mem_data_t       mem_read_data,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe
);

  localparam int unsigned WordBits = $bits(mem_addr);
  initial begin
    assert (NumGpio < WordBits);
  end

  logic [NumGpio-1:0] _read;


  assign selected = mem_addr == GpioDataInAddr || mem_addr == GpioDataOutAddr || mem_addr == GpioDirAddr ||
             mem_addr == GpioSetAddr || mem_addr == GpioClearAddr || mem_addr == GpioToggleAddr;
  assign mem_ready = mem_valid && selected;

  always_ff @(posedge clk) begin
    if (rst) begin
      gpio_out <= 0;
      gpio_oe  <= 0;
    end else begin
      if (mem_write_en && selected) begin
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

  assign _read = mem_addr == GpioDataInAddr ? gpio_in :
                   mem_addr == GpioDataOutAddr ? gpio_out :
                   mem_addr == GpioDirAddr ? gpio_oe :
                   8'h0;

  assign mem_read_data = {{WordBits - NumGpio{1'b0}}, _read};

endmodule
