#include "board.h"
#include "riscv_soc/sim.h"

int main(void) {
  uart_putc('o');
  uart_putc('k');
  uart_putc('\n');

  while (!uart_tx_ready()) {
  }

  sim_halt(0);
}
