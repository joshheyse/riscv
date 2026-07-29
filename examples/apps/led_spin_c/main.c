#include "board.h"

int main(void) {
  uint32_t led = 1u;

  for (;;) {
    led_write(led);
    sleep_ms(50);

    led = (led << 1) & 0xffu;
    if (led == 0u) {
      led = 1u;
    }
  }

  return 0;
}
