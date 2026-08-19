`timescale 1ns / 1ps

// SPI master-side interface for top-level pin wiring.
// SoC drives `sck`, `mosi`, and `cs_n`; external master/slave drives `miso`.
interface spi_if
  import riscv_pkg::*;
();

  logic sck;  // serial clock
  logic mosi;  // master out / slave in
  logic miso;  // master in / slave out
  logic cs_n;  // active-low chip-select

  modport source(output sck, output mosi, output cs_n, input miso);

  modport sink(input sck, input mosi, input cs_n, output miso);

endinterface
