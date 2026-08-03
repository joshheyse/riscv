`timescale 1ns / 1ps

module dip_switch_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   DipSwitchAddr  = '0,
  parameter int unsigned NumDipSwitches = 1
) (
  input  logic                                 mem_valid,
  input  logic                                 mem_write_en,
  input  mem_addr_t                            mem_addr,
  input  mem_data_t                            mem_write_data,
  input  mem_write_mask_t                      mem_write_mask,
  output logic                                 selected,
  output logic                                 mem_ready,
  output mem_data_t                            mem_read_data,
  input  logic            [NumDipSwitches-1:0] dip_switch
);

  localparam int unsigned WordBits = $bits(mem_addr);
  initial begin
    assert (NumDipSwitches < WordBits);
  end

  assign selected = (mem_addr == DipSwitchAddr);
  assign mem_ready = mem_valid && selected;

  assign mem_read_data = {{(WordBits - NumDipSwitches) {1'b0}}, dip_switch};

  logic _unused_write_bus;
  assign _unused_write_bus = mem_write_en | (|mem_write_data) | (|mem_write_mask);

endmodule
