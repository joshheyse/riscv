`timescale 1ns / 1ps

// Lattice ECP5 Evaluation Board bus and memory-mapped peripherals.
module sdram_controller
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst,

  mem_if.slave    mem,
  sdram_if.source sdram
);

  typedef enum logic [3:0] {
    RESET_WAIT,
    PRECHARGE_ALL,
    REFRESH_1,
    REFRESH_2,
    LOAD_MODE,
    IDLE,
    ACTIVATE,
    READ_WAIT,
    READ_BURST,
    WRITE_BURST,
    PRECHARGE,
    RESPOND,
    REFRESH
  } state_t;

  state_t   _state;

  mem_req_t _mem_req;

  always_comb begin
    for (int i = 0; i < 32; i++) begin
      sdram.a[i] = _mem_req.addr[i];
    end

  end

  always_ff @(posedge clk) begin
    if (rst) begin
      _state <= RESET_WAIT;
    end
  end

endmodule
