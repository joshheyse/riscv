`timescale 1ns / 1ps

interface mem_if
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
    logic      ready;
    mem_data_t read_data;
  } rsp_t;

  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  req_t req;
  rsp_t rsp;
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  modport master(output req, input rsp);
  modport slave(input req, output rsp);

endinterface
