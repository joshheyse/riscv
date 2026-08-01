`timescale 1ns / 1ps

interface dbus_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic            valid;
    logic            write_en;
    word_t           addr;
    word_t           write_data;
    mem_write_mask_t write_mask;
  } req_t;

  typedef struct packed {
    logic  ready;
    word_t read_data;
  } rsp_t;

  req_t req;
  rsp_t rsp;

  modport master(output req, input rsp);

  modport slave(input req, output rsp);

endinterface
