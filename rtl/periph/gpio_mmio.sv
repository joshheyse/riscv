`timescale 1ns / 1ps

module gpio_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   GpioDataInAddr  = 32'h10006000,
  parameter mem_addr_t   GpioDataOutAddr = 32'h10006004,
  parameter mem_addr_t   GpioDirAddr     = 32'h10006008,
  parameter mem_addr_t   GpioSetAddr     = 32'h1000600C,
  parameter mem_addr_t   GpioClearAddr   = 32'h10006010,
  parameter mem_addr_t   GpioToggleAddr  = 32'h10006014,
  parameter int unsigned NumGpio         = 1
) (
  input logic clk,
  input logic rst,

  input  logic [NumGpio-1:0] gpio_in,
  output logic [NumGpio-1:0] gpio_out,
  output logic [NumGpio-1:0] gpio_oe,
  output logic               selected,

  mem_if.slave mem
);

  localparam int unsigned WordBits = $bits(mem_addr_t);
  initial begin
    assert (NumGpio < WordBits);
    assert (GpioDataInAddr != GpioDataOutAddr);
    assert (GpioDataInAddr != GpioDirAddr);
    assert (GpioDataInAddr != GpioSetAddr);
    assert (GpioDataInAddr != GpioClearAddr);
    assert (GpioDataInAddr != GpioToggleAddr);
    assert (GpioDataOutAddr != GpioDirAddr);
    assert (GpioDataOutAddr != GpioSetAddr);
    assert (GpioDataOutAddr != GpioClearAddr);
    assert (GpioDataOutAddr != GpioToggleAddr);
    assert (GpioDirAddr != GpioSetAddr);
    assert (GpioDirAddr != GpioClearAddr);
    assert (GpioDirAddr != GpioToggleAddr);
    assert (GpioSetAddr != GpioClearAddr);
    assert (GpioSetAddr != GpioToggleAddr);
    assert (GpioClearAddr != GpioToggleAddr);
  end

  logic [NumGpio-1:0] _read;

  always_comb begin
    case (mem.req.addr)
      GpioDataInAddr,
      GpioDataOutAddr,
      GpioDirAddr,
      GpioSetAddr,
      GpioClearAddr,
      GpioToggleAddr:
      begin
        selected = 1'b1;
      end
      default: selected = 1'b0;
    endcase
  end

  assign mem.rsp.ready = mem.req.valid && selected;

  always_ff @(posedge clk) begin
    if (rst) begin
      gpio_out <= 0;
      gpio_oe  <= 0;
    end else begin
      if (mem.req.write_en && selected) begin
        case (mem.req.addr)
          GpioDataOutAddr: begin
            gpio_out <= mem.req.write_data[NumGpio-1:0];
          end
          GpioDirAddr: begin
            gpio_oe <= mem.req.write_data[NumGpio-1:0];
          end
          GpioSetAddr: begin
            gpio_out <= gpio_out | mem.req.write_data[NumGpio-1:0];
          end
          GpioClearAddr: begin
            gpio_out <= gpio_out & ~mem.req.write_data[NumGpio-1:0];
          end
          GpioToggleAddr: begin
            gpio_out <= gpio_out ^ mem.req.write_data[NumGpio-1:0];
          end
          default: begin
          end
        endcase
      end
    end
  end

  always_comb begin
    case (mem.req.addr)
      GpioDataInAddr:  _read = gpio_in;
      GpioDataOutAddr: _read = gpio_out;
      GpioDirAddr:     _read = gpio_oe;
      default:         _read = {NumGpio{1'b0}};
    endcase
  end

  always_comb begin
    mem.rsp.read_data = '0;
    mem.rsp.read_data = {{WordBits - NumGpio{1'b0}}, _read};
  end

endmodule
