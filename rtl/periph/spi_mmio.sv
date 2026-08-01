`timescale 1ns / 1ps

typedef enum logic [2:0] {
  SPI_IDLE     = 3'b000,
  SPI_SETUP    = 3'b010,
  SPI_SCK_HIGH = 3'b011,
  SPI_SCK_LOW  = 3'b100,
  SPI_DONE     = 3'b101
} spi_state_t;

module spi_mmio
  import riscv_pkg::*;
#(
  parameter word_t       DataAddr         = '0,
  parameter word_t       ControlAddr      = '0,
  parameter word_t       StatusAddr       = '0,
  parameter int unsigned ClocksPerHalfBit = 1
) (
  input logic clk,
  input logic rst,

  input  logic            mem_valid,
  input  logic            mem_write_en,
  input  word_t           mem_addr,
  input  word_t           mem_write_data,
  input  mem_write_mask_t mem_write_mask,
  output logic            selected,
  output logic            mem_ready,
  output word_t           mem_read_data,

  output logic spi_sck,
  output logic spi_mosi,
  input  logic spi_miso,
  output logic spi_cs_n
);

  spi_state_t       _state;
  logic             _busy;
  logic             _data_selected;
  logic             _control_selected;
  logic             _status_selected;
  byte_t            _tx_data;
  byte_t            _rx_data;
  logic       [2:0] _bit_index;

  assign _data_selected = mem_addr == DataAddr;
  assign _control_selected = mem_addr == ControlAddr;
  assign _status_selected = mem_addr == StatusAddr;
  assign selected = _data_selected || _control_selected || _status_selected;
  assign mem_ready = mem_valid && selected;

  logic _stg_en;
  logic _stg_clear;
  logic _stg_tick;

  assign _stg_en = (_state == SPI_SCK_HIGH || _state == SPI_SCK_LOW);
  assign _stg_clear = !_stg_en;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerHalfBit)
  ) _tick_generator (
    .clk(clk),
    .rst(rst),
    .en(_stg_en),
    .clear(_stg_clear),
    .tick(_stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= SPI_IDLE;
      _tx_data <= 0;
      _rx_data <= 0;
      _bit_index <= 0;
    end else begin
      if (mem_write_en && _data_selected) begin
        _tx_data <= mem_write_data[7:0];
      end
      unique case (_state)
        SPI_IDLE: begin
          if (mem_write_en && _control_selected && mem_write_data[0]) begin
            _bit_index <= 3'b111;
            _rx_data <= 0;
            _state <= SPI_SETUP;
          end
        end
        SPI_SETUP: begin
          _state <= SPI_SCK_HIGH;
        end
        SPI_SCK_HIGH: begin
          _rx_data[_bit_index] <= spi_miso;
          if (_stg_tick) begin
            _state <= SPI_SCK_LOW;
          end
        end
        SPI_SCK_LOW: begin
          if (_stg_tick) begin
            if (_bit_index == 3'b000) begin
              _state <= SPI_DONE;
            end else begin
              _bit_index <= _bit_index - 1'b1;
              _state <= SPI_SETUP;
            end
          end
        end
        SPI_DONE: begin
          _state <= SPI_IDLE;
        end
      endcase
    end
  end

  always_comb begin
    spi_sck = 1'b0;
    spi_cs_n = 1'b1;
    _busy = 1'b0;
    spi_mosi = 1'b0;

    case (_state)
      SPI_SETUP, SPI_SCK_LOW, SPI_SCK_HIGH: begin
        _busy = 1'b1;
        spi_cs_n = 1'b0;
        spi_mosi = _tx_data[_bit_index];
      end
      default: begin
      end
    endcase

    if (_state == SPI_SCK_HIGH) begin
      spi_sck = 1'b1;
    end

    if (_data_selected) begin
      mem_read_data = {24'b0, _rx_data};
    end else if (_status_selected) begin
      mem_read_data = {31'b0, _busy};
    end else begin
      mem_read_data = 32'b0;
    end
  end

  logic _unused_write_data;
  assign _unused_write_data = |mem_write_data[31:8] | (|mem_write_mask);

endmodule
