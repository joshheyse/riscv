`timescale 1ns / 1ps

module uart_mmio
  import riscv_pkg::*;
#(
  parameter int unsigned ClocksPerBit = 1,
  parameter mem_addr_t   TxDataAddr   = 32'h10001000,
  parameter mem_addr_t   StatusAddr   = 32'h1000100C
) (
  input logic clk,
  input logic rst,

  output logic tx,
  output logic selected,

  mem_if.slave mem
);

  byte_t       _tx_data;
  logic  [3:0] _bit_idx;
  logic  [2:0] _data_bit_idx;
  logic        _tx_busy;
  logic        _tx_ready;

  initial begin
    assert (TxDataAddr != StatusAddr);
  end

  assign selected = (mem.req.addr == TxDataAddr | mem.req.addr == StatusAddr);
  assign mem.rsp.ready = mem.req.valid && selected;

  assign _tx_ready = !_tx_busy;
  always_comb begin
    mem.rsp.read_data = 32'h0;
    mem.rsp.read_data = (mem.req.addr == StatusAddr) ? {31'b0, _tx_ready} : 32'h0;
  end
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
    end else if (mem.req.write_en && (mem.req.addr == TxDataAddr) && !_tx_busy) begin
      _tx_busy <= 1'b1;
      _tx_data <= mem.req.write_data[7:0];
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

endmodule
