`timescale 1ns / 1ps

// typedef enum logic [2:0] {
//   SPI_IDLE     = 3'b000,
//   SPI_LOAD_BIT = 3'b001,
//   SPI_SETUP    = 3'b010,
//   SPI_SCK_HIGH = 3'b011,
//   SPI_SCK_LOW  = 3'b100,
//   SPI_DONE     = 3'b101
// } spi_state_t;

module i2c_mmio #(
  parameter riscv_pkg::word_t DataAddr = memmap_pkg::I2cDataAddr,
  parameter riscv_pkg::word_t ControlAddr = memmap_pkg::I2cControlAddr,
  parameter riscv_pkg::word_t StatusAddr = memmap_pkg::I2cStatusAddr,
  parameter riscv_pkg::word_t AddressAddr = memmap_pkg::I2cAddressAddr
) (
  input logic clk,
  input logic rst,
  input logic mem_write,
  input riscv_pkg::word_t mem_addr,
  input riscv_pkg::word_t mem_write_data,
  output logic selected,
  output riscv_pkg::word_t read_data,
  input logic i2c_sda_in,
  output logic i2c_sda_drive_low,
  input logic i2c_scl_in,
  output logic i2c_scl_drive_low
);

  logic data_selected;
  logic control_selected;
  logic status_selected;
  logic address_selected;

  assign data_selected = mem_addr == DataAddr;
  assign control_selected = mem_addr == ControlAddr;
  assign status_selected = mem_addr == StatusAddr;
  assign address_selected = mem_addr == AddressAddr;
  assign selected = data_selected || control_selected || status_selected || address_selected;

  assign read_data = 0;
  assign i2c_sda_drive_low = 0;
  assign i2c_scl_drive_low = 0;

  logic unused_inputs;

  assign unused_inputs = clk | rst | mem_write | i2c_sda_in | i2c_scl_in | (|mem_write_data);

endmodule
