#include "board.h"

static void put_result(uint32_t errors) {
  uart_putc(errors == 0u ? 'P' : 'F');
  uart_putc('\n');
}

int main(void) {
  volatile uint32_t src[4];
  volatile uint32_t dst[4];
  uint32_t errors = 0;

  src[0] = 0x00000001u;
  src[1] = 0x80000000u;
  src[2] = 0x12345678u;
  src[3] = 0xffffffffu;

  for (uint32_t i = 0; i < 4u; i++) {
    dst[i] = src[i];
  }

  for (uint32_t i = 0; i < 4u; i++) {
    if (dst[i] != src[i]) {
      errors = errors + 1u;
    }
  }

  led_write(errors == 0u ? 0x5au : 0xffu);
  put_result(errors);

  while (!uart_tx_ready()) {
  }

  halt(errors);
  return 0;
}
