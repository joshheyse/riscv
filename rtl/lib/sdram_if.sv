`timescale 1ns / 1ps

// Synchronous DRAM pin-side interface.
//
// The board has two SDRAM devices sharing the address, bank, command, clock,
// mask, and 16-bit data buses.  Their separate chip-selects select which
// device (rank) is active.  The data bus is split into input/output/enable
// signals here so the board wrapper can own the actual top-level tri-state:
//
//   assign sdram_dq = sdram.dq_oe ? sdram.dq_out : 'z;
//   assign sdram.dq_in = sdram_dq;
//
// DQM[0] masks DQ[7:0]; DQM[1] masks DQ[15:8].
interface sdram_if
  import riscv_pkg::*;
();

  localparam int unsigned AddressBits = 13;
  localparam int unsigned BankBits    = 2;
  localparam int unsigned DataBits    = 16;
  localparam int unsigned MaskBits    = DataBits / 8;

  logic [AddressBits-1:0] a;
  logic [BankBits-1:0]    ba;
  logic [DataBits-1:0]    dq_out;
  logic [DataBits-1:0]    dq_in;
  logic                   dq_oe;
  logic [MaskBits-1:0]    dqm;

  logic                   cs0_n;
  logic                   cs1_n;
  logic                   ras_n;
  logic                   cas_n;
  logic                   we_n;
  logic                   cke;
  logic                   sdram_clk;

  // Controller drives the SDRAM command/address/data-output side and samples
  // the data input side.
  modport source(
      output a,
      output ba,
      output dq_out,
      output dq_oe,
      output dqm,
      output cs0_n,
      output cs1_n,
      output ras_n,
      output cas_n,
      output we_n,
      output cke,
      output sdram_clk,
      input  dq_in
  );

  // Board wrapper consumes controller outputs and feeds back the sampled
  // physical data bus.
  modport sink(
      input  a,
      input  ba,
      input  dq_out,
      input  dq_oe,
      input  dqm,
      input  cs0_n,
      input  cs1_n,
      input  ras_n,
      input  cas_n,
      input  we_n,
      input  cke,
      input  sdram_clk,
      output dq_in
  );

endinterface
