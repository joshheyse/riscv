`timescale 1ns / 1ps

module irq_aggregator #(
  parameter int unsigned N
) (
  input  logic         [N-1:0] meip_src,
  input  logic         [N-1:0] msip_src,
  input  logic         [N-1:0] mtip_src,
  output irq_if.source         irq
);
  always_comb begin
    irq.pending = '0;
    irq.pending.meip = |meip_src;
    irq.pending.mtip = |mtip_src;
    irq.pending.msip = |msip_src;
  end
endmodule
