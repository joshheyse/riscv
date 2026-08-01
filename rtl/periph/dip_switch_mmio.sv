`timescale 1ns / 1ps

module dip_switch_mmio
  import riscv_pkg::*;
#(
  parameter word_t DipSwitchAddr = '0,
  parameter int unsigned NumDipSwitches = 1
) (
  input word_t mem_addr,
  output logic selected,
  output word_t read_data,
  input logic [NumDipSwitches-1:0] dip_switch
);

  localparam int unsigned WordBits = $bits(mem_addr);
  initial begin
    assert (NumDipSwitches < WordBits);
  end

  assign selected  = (mem_addr == DipSwitchAddr);

  assign read_data = {{(WordBits - NumDipSwitches) {1'b0}}, dip_switch};

endmodule
