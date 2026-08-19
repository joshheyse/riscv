`timescale 1ns / 1ps

// I2C line-level interface.
//
// The bus is open-drain on SCL/SDA in the SoC/board bus path:
// - `*_drive_low = 1` means the core actively drives that line low.
// - `*_drive_low = 0` means the core releases the line (tri-stated at the board
//   boundary), so an external pull-up or another agent can hold it high.
interface i2c_if
  import riscv_pkg::*;
();

  logic sda_in;  // sampled SDA input level
  logic sda_drive_low;  // 1 drives SDA low, 0 releases SDA
  /* verilator lint_off UNUSEDSIGNAL */
  logic scl_in;  // sampled SCL input level
  /* verilator lint_on UNUSEDSIGNAL */
  logic scl_drive_low;  // 1 drives SCL low, 0 releases SCL

  modport source(input sda_in, input scl_in, output sda_drive_low, output scl_drive_low);

  modport sink(output sda_in, output scl_in, input sda_drive_low, input scl_drive_low);

endinterface
