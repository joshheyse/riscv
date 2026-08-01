`timescale 1ns / 1ps

typedef enum logic [2:0] {
  SPI_IDLE     = 3'b000,
  SPI_SETUP    = 3'b010,
  SPI_SCK_HIGH = 3'b011,
  SPI_SCK_LOW  = 3'b100,
  SPI_DONE     = 3'b101
} spi_state_t;

module spi_mmio #(
  parameter riscv_pkg::word_t DataAddr = '0,
  parameter riscv_pkg::word_t ControlAddr = '0,
  parameter riscv_pkg::word_t StatusAddr = '0,
  parameter int unsigned ClocksPerHalfBit = 1
) (
  input logic clk,
  input logic rst,

  input logic mem_write_en,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,

  output logic spi_sck,
  output logic spi_mosi,
  input  logic spi_miso,
  output logic spi_cs_n
);

  spi_state_t state;
  logic busy;
  logic data_selected;
  logic control_selected;
  logic status_selected;
  riscv_pkg::byte_t tx_data;
  riscv_pkg::byte_t rx_data;
  logic [2:0] bit_index;

  assign data_selected = mem_addr == DataAddr;
  assign control_selected = mem_addr == ControlAddr;
  assign status_selected = mem_addr == StatusAddr;
  assign selected = data_selected || control_selected || status_selected;

  logic stg_enabled;
  logic stg_clear;
  logic stg_tick;

  assign stg_enabled = (state == SPI_SCK_HIGH || state == SPI_SCK_LOW);
  assign stg_clear   = !stg_enabled;

  serial_tick_generator #(
    .ClocksPerTick(ClocksPerHalfBit)
  ) stg (
    .clk(clk),
    .rst(rst),
    .enable(stg_enabled),
    .clear(stg_clear),
    .tick(stg_tick)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= SPI_IDLE;
      tx_data <= 0;
      rx_data <= 0;
      bit_index <= 0;
    end else begin
      if (mem_write_en && data_selected) begin
        tx_data <= mem_write_data[7:0];
      end
      unique case (state)
        SPI_IDLE: begin
          if (mem_write_en && control_selected && mem_write_data[0]) begin
            bit_index <= 3'b111;
            rx_data <= 0;
            state <= SPI_SETUP;
          end
        end
        SPI_SETUP: begin
          state <= SPI_SCK_HIGH;
        end
        SPI_SCK_HIGH: begin
          rx_data[bit_index] <= spi_miso;
          if (stg_tick) begin
            state <= SPI_SCK_LOW;
          end
        end
        SPI_SCK_LOW: begin
          if (stg_tick) begin
            if (bit_index == 3'b000) begin
              state <= SPI_DONE;
            end else begin
              bit_index <= bit_index - 1'b1;
              state <= SPI_SETUP;
            end
          end
        end
        SPI_DONE: begin
          state <= SPI_IDLE;
        end
      endcase
    end
  end

  always_comb begin
    spi_sck = 1'b0;
    spi_cs_n = 1'b1;
    busy = 1'b0;
    spi_mosi = 1'b0;

    case (state)
      SPI_SETUP, SPI_SCK_LOW, SPI_SCK_HIGH: begin
        busy = 1'b1;
        spi_cs_n = 1'b0;
        spi_mosi = tx_data[bit_index];
      end
      default: begin
      end
    endcase

    if (state == SPI_SCK_HIGH) begin
      spi_sck = 1'b1;
    end

    if (data_selected) begin
      read_data = {24'b0, rx_data};
    end else if (status_selected) begin
      read_data = {31'b0, busy};
    end else begin
      read_data = 32'b0;
    end
  end

  logic unused_write_data;
  assign unused_write_data = |mem_write_data[31:8];

endmodule
