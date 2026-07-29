`timescale 1ns / 1ps

module dip_switch_mmio #(
  parameter riscv_pkg::word_t DipSwitchAddr = memmap_pkg::DipSwitchAddr,
  parameter int unsigned NumDipSwitches = memmap_pkg::NumDipSwitches
) (
  input riscv_pkg::word_t mem_addr,
  output logic selected,
  output riscv_pkg::word_t read_data,
  input logic [NumDipSwitches-1:0] dip_switch
);

  localparam int unsigned WordBits = 32;
  initial begin
    assert (NumDipSwitches < WordBits);
  end

  assign selected  = (mem_addr == DipSwitchAddr);

  assign read_data = {{(WordBits - NumDipSwitches) {1'b0}}, dip_switch};

endmodule
