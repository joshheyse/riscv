`timescale 1ns / 1ps

// UART pin-level interface used between board/IO and a UART peripheral.
// `tx` is driven by the SoC side (UART peripheral).
// `rx` is sampled from the board pin side.
interface uart_if
  import riscv_pkg::*;
();

  logic tx;  // UART transmit output
  logic rx;  // UART receive input

  modport source(
    output tx,
    input  rx
  );

  modport sink(
    input  tx,
    output rx
  );

endinterface
