`timescale 1ns / 1ps

interface dbus_if
  import riscv_pkg::*;
();

  logic            valid;
  logic            ready;
  word_t           addr;

  logic            write_en;
  word_t           write_data;

  mem_write_mask_t write_mask;

  word_t           read_data;

  modport master(
      output valid,
      input ready,

      output addr,
      input read_data,

      output write_en,
      output write_data,
      output write_mask
  );

  modport slave(
      input valid,
      output ready,

      input addr,
      output read_data,

      input write_en,
      input write_data,
      input write_mask
  );

endinterface
