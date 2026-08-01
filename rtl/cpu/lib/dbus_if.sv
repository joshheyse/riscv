`timescale 1ns / 1ps

interface dbus_if
  import riscv_pkg::*;
();

  logic      valid;
  logic      write_en;
  word_t     addr;
  word_t     write_data;
  word_t     read_data;
  logic      ready;
  mem_size_t size;
  logic      mem_unsigned;

  modport master(
      output valid,
      output write_en,
      output addr,
      output write_data,
      output size,
      output mem_unsigned,
      input read_data,
      input ready
  );

  modport slave(
      input valid,
      input write_en,
      input addr,
      input write_data,
      input size,
      input mem_unsigned,
      output read_data,
      output ready
  );

endinterface
