#include "board.h"

int main(void) {
  for (uint32_t i = 0; i < 8u; i++) {
    led_write(1u << i);
    timer_sleep_cycles(1024u);
  }

  led_write(0xaau);
  halt(0);
  return 0;
}
