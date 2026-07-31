`timescale 1ns / 1ps

module uart_mmio #(
  parameter int unsigned      ClocksPerBit = memmap_pkg::UartClocksPerBit,
  parameter riscv_pkg::word_t TxDataAddr   = memmap_pkg::UartTxAddr,
  parameter riscv_pkg::word_t StatusAddr   = memmap_pkg::UartStatusAddr
) (
  input logic clk,
  input logic rst,

  input logic mem_write,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,
  output logic tx
);

  riscv_pkg::byte_t tx_data;
  logic [3:0] bit_idx;
  logic [2:0] data_bit_idx;
  logic tx_busy;
  logic tx_ready;

  assign selected  = (mem_addr == TxDataAddr | mem_addr == StatusAddr);

  assign tx_ready  = !tx_busy;
  assign read_data = (mem_addr == StatusAddr) ? {31'b0, tx_ready} : 32'h0;
  assign data_bit_idx = bit_idx[2:0] - 3'd1;

  logic stg_enabled;
  logic stg_clear;
  logic stg_tick;

  assign stg_enabled = tx_busy;
  assign stg_clear   = !stg_enabled;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerBit)
  ) stg (
    .clk(clk),
    .rst(rst),
    .enable(stg_enabled),
    .clear(stg_clear),
    .tick(stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      tx_busy <= 1'b0;
      tx_data <= 8'h0;
      bit_idx <= '0;
    end else if (mem_write && (mem_addr == TxDataAddr) && !tx_busy) begin
      tx_busy <= 1'b1;
      tx_data <= mem_write_data[7:0];
      bit_idx <= 0;
    end else if (tx_busy) begin
      if (stg_tick) begin
        bit_idx <= bit_idx + 4'd1;
        if (bit_idx == 4'd9) begin
          tx_busy <= 1'b0;
        end
      end
    end
  end

  always_comb begin
    if (!tx_busy) begin
      tx = 1'b1;
    end else if (bit_idx == 4'd0) begin
      tx = 1'b0;
    end else if (bit_idx <= 4'd8) begin
      tx = tx_data[data_bit_idx];
    end else begin
      tx = 1'b1;
    end
  end

  localparam int unsigned WordBits = $bits(riscv_pkg::word_t);
  logic unused_write_data;
  assign unused_write_data = |mem_write_data[WordBits-1:8];

endmodule
