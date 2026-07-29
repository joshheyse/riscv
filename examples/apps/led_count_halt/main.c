#include "board.h"
#include "riscv_soc/sim.h"

static void delay(void) {
  volatile uint32_t i = 0;
  while (i < 1024u) {
    i = i + 1u;
  }
}

int main(void) {
  for (uint32_t i = 0; i < 8u; i++) {
    led_write(1u << i);
    delay();
  }

  led_write(0xaau);
  sim_halt(0);
}
