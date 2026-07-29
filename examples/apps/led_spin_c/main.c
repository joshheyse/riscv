#include "board.h"

static void delay(void) {
  for (volatile uint32_t i = 0; i < 600000u; i++) {
  }
}

int main(void) {
  uint32_t led = 1u;

  for (;;) {
    led_write(led);
    delay();

    led = (led << 1) & 0xffu;
    if (led == 0u) {
      led = 1u;
    }
  }
}
