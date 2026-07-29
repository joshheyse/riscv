#include "board.h"
#include "riscv_soc/sim.h"

int main(void) {
  for (uint32_t i = 0; i < 8u; i++) {
    led_write(1u << i);
    timer_sleep_cycles(1024u);
  }

  led_write(0xaau);
  sim_halt(0);
  return 0;
}
