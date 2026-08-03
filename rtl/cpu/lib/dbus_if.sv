`timescale 1ns / 1ps

interface dbus_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic            valid;
    logic            write_en;
    mem_addr_t       addr;
    mem_data_t       write_data;
    mem_write_mask_t write_mask;
  } req_t;

  typedef struct packed {
    logic ready;
    mem_data_t read_data;
  } rsp_t;

  req_t req;
  rsp_t rsp;

  modport master(output req, input rsp);

  modport slave(input req, output rsp);

endinterface
