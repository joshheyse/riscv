`timescale 1ns / 1ps

module dip_switch_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   DipSwitchAddr  = '0,
  parameter int unsigned NumDipSwitches = 1
) (
  input  logic                                 mem_valid,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                                 mem_write_en,
  /* verilator lint_on UNUSEDSIGNAL */
  input  mem_addr_t                            mem_addr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  mem_data_t                            mem_write_data,
  input  mem_write_mask_t                      mem_write_mask,
  /* verilator lint_on UNUSEDSIGNAL */
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

endmodule
