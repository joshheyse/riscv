#include "board.h"

int main(void) {
  uart_putc('o');
  uart_putc('k');
  uart_putc('\n');

  while (!uart_tx_ready()) {
  }

  halt(0);
  return 0;
}
