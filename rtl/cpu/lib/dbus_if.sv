`timescale 1ns / 1ps

interface dbus_if
  import riscv_pkg::*;
();

  typedef struct packed {
    logic            valid;       // request valid; one request at a time
    logic            write_en;    // 1 = store/write transaction, 0 = load/read
    mem_addr_t       addr;        // target byte address
    mem_data_t       write_data;  // write payload
    mem_write_mask_t write_mask;  // active byte lanes for writes
  } req_t;

  typedef struct packed {
    logic      ready;      // transaction can complete this cycle
    mem_data_t read_data;  // read payload when ready=1 and write_en=0
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
