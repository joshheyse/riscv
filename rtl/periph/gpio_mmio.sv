`timescale 1ns / 1ps

module gpio_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t  GpioDataInAddr  = '0,
  parameter mem_addr_t  GpioDataOutAddr = '0,
  parameter mem_addr_t  GpioDirAddr     = '0,
  parameter mem_addr_t  GpioSetAddr     = '0,
  parameter mem_addr_t  GpioClearAddr   = '0,
  parameter mem_addr_t  GpioToggleAddr  = '0,
  parameter int unsigned NumGpio         = 1
) (
  input  logic               clk,
  input  logic               rst,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe,
  output logic               selected,

  mem_if.slave mem
);

  localparam int unsigned WordBits = $bits(mem_addr_t);
  initial begin
    assert (NumGpio < WordBits);
  end

  logic [NumGpio-1:0] _read;


  assign selected = mem.req.addr == GpioDataInAddr || mem.req.addr == GpioDataOutAddr || mem.req.addr == GpioDirAddr ||
                   mem.req.addr == GpioSetAddr || mem.req.addr == GpioClearAddr || mem.req.addr == GpioToggleAddr;
  assign mem.rsp.ready = mem.req.valid && selected;

  always_ff @(posedge clk) begin
    if (rst) begin
      gpio_out <= 0;
      gpio_oe  <= 0;
    end else begin
      if (mem.req.write_en && selected) begin
        if (mem.req.addr == GpioDataOutAddr) begin
          gpio_out <= mem.req.write_data[NumGpio-1:0];
        end else if (mem.req.addr == GpioDirAddr) begin
          gpio_oe <= mem.req.write_data[NumGpio-1:0];
        end else if (mem.req.addr == GpioSetAddr) begin
          gpio_out <= gpio_out | mem.req.write_data[NumGpio-1:0];
        end else if (mem.req.addr == GpioClearAddr) begin
          gpio_out <= gpio_out & ~mem.req.write_data[NumGpio-1:0];
        end else if (mem.req.addr == GpioToggleAddr) begin
          gpio_out <= gpio_out ^ mem.req.write_data[NumGpio-1:0];
        end
      end
    end
  end

  assign _read = mem.req.addr == GpioDataInAddr ? gpio_in :
                mem.req.addr == GpioDataOutAddr ? gpio_out :
                mem.req.addr == GpioDirAddr ? gpio_oe :
                {NumGpio{1'b0}};

  always_comb begin
    mem.rsp.read_data = '0;
    mem.rsp.read_data = {{WordBits - NumGpio{1'b0}}, _read};
  end

endmodule
