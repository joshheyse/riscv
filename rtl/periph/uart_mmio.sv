`timescale 1ns / 1ps

module uart_mmio
  import riscv_pkg::*;
#(
  parameter int unsigned ClocksPerBit = 1,
  parameter word_t       TxDataAddr   = '0,
  parameter word_t       StatusAddr   = '0
) (
  input logic clk,
  input logic rst,

  input  logic  mem_write_en,
  input  word_t mem_addr,
  input  word_t mem_write_data,
  output logic  selected,
  output word_t read_data,
  output logic  tx
);

  byte_t       _tx_data;
  logic  [3:0] _bit_idx;
  logic  [2:0] _data_bit_idx;
  logic        _tx_busy;
  logic        _tx_ready;

  assign selected = (mem_addr == TxDataAddr | mem_addr == StatusAddr);

  assign _tx_ready = !_tx_busy;
  assign read_data = (mem_addr == StatusAddr) ? {31'b0, _tx_ready} : 32'h0;
  assign _data_bit_idx = _bit_idx[2:0] - 3'd1;

  logic _stg_en;
  logic _stg_clear;
  logic _stg_tick;

  assign _stg_en = _tx_busy;
  assign _stg_clear = !_stg_en;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerBit)
  ) _tick_generator (
    .clk(clk),
    .rst(rst),
    .en(_stg_en),
    .clear(_stg_clear),
    .tick(_stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      _tx_busy <= 1'b0;
      _tx_data <= 8'h0;
      _bit_idx <= '0;
    end else if (mem_write_en && (mem_addr == TxDataAddr) && !_tx_busy) begin
      _tx_busy <= 1'b1;
      _tx_data <= mem_write_data[7:0];
      _bit_idx <= 0;
    end else if (_tx_busy) begin
      if (_stg_tick) begin
        _bit_idx <= _bit_idx + 4'd1;
        if (_bit_idx == 4'd9) begin
          _tx_busy <= 1'b0;
        end
      end
    end
  end

  always_comb begin
    if (!_tx_busy) begin
      tx = 1'b1;
    end else if (_bit_idx == 4'd0) begin
      tx = 1'b0;
    end else if (_bit_idx <= 4'd8) begin
      tx = _tx_data[_data_bit_idx];
    end else begin
      tx = 1'b1;
    end
  end

  localparam int unsigned WordBits = $bits(mem_addr);
  logic _unused_write_data;
  assign _unused_write_data = |mem_write_data[WordBits-1:8];

endmodule
