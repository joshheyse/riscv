`timescale 1ns / 1ps

module dip_switch_mmio
  import riscv_pkg::*;
#(
  parameter mem_addr_t   DipSwitchAddr  = 32'h10003000,
  parameter int unsigned NumDipSwitches = 1
) (
  input logic [NumDipSwitches-1:0] dip_switch,

  output logic selected,

  mem_if.slave mem
);
  localparam int unsigned WordBits = $bits(mem_addr_t);
  initial begin
    assert (NumDipSwitches < WordBits);
  end

  assign selected = (mem.req.addr == DipSwitchAddr);
  assign mem.rsp.ready = mem.req.valid && selected;

  always_comb begin
    mem.rsp.read_data = '0;
    mem.rsp.read_data = {{(WordBits - NumDipSwitches) {1'b0}}, dip_switch};
  end

endmodule
