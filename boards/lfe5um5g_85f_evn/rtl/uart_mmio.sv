`timescale 1ns / 1ps

module uart_mmio #(
  parameter integer unsigned  ClocksPerBit = 104,
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
  logic tx_busy;
  logic tx_ready;

  assign selected = (mem_addr == TxDataAddr || mem_addr == StatusAddr);

  localparam int unsigned BaudCounterBits = $clog2(ClocksPerBit);
  localparam logic [BaudCounterBits-1:0] BaudTerminal = BaudCounterBits'(ClocksPerBit - 1);

  logic [BaudCounterBits-1:0] baud_count;

  assign tx_ready  = !tx_busy;
  assign read_data = (mem_addr == StatusAddr) ? {31'b0, tx_ready} : 32'h0;

  always_ff @(posedge clk) begin
    if (rst) begin
      tx_busy <= 1'b0;
      tx_data <= 8'h0;
      bit_idx <= 0;
      baud_count <= 0;
    end else if (mem_write && (mem_addr == TxDataAddr) && !tx_busy) begin
      tx_busy <= 1'b1;
      tx_data <= mem_write_data[7:0];
      bit_idx <= 0;
      baud_count <= 0;
    end else if (tx_busy) begin
      if (baud_count == BaudTerminal) begin
        baud_count <= 0;
        bit_idx <= bit_idx + 1;
        if (bit_idx == 4'd9) begin
          tx_busy <= 1'b0;
        end
      end else begin
        baud_count <= baud_count + 1;
      end
    end
  end

  always_comb begin
    if (!tx_busy) begin
      tx = 1'b1;
    end else if (bit_idx == 4'd0) begin
      tx = 1'b0;
    end else if (bit_idx <= 4'd8) begin
      tx = tx_data[bit_idx-1];
    end else begin
      tx = 1'b1;
    end
  end

  localparam int unsigned WordBits = 32;
  logic unused_write_data;
  assign unused_write_data = |mem_write_data[WordBits-1:8];

endmodule
