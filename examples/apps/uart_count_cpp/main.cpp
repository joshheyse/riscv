#include "board.h"

static void put_hex_digit(uint32_t value) {
  value &= 0xfu;
  uart_putc(value < 10u ? char('0' + value) : char('a' + value - 10u));
}

int main() {
  uint32_t value = 0u;

  for (;;) {
    led_write(value);
    put_hex_digit(value);
    uart_putc('\n');
    value = (value + 1u) & 0xffu;
    sleep_ms(250);
  }
}
