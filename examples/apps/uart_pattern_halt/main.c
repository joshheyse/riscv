#include "board.h"
#include "riscv_soc/sim.h"

static void put_hex_digit(uint32_t value) {
  value = value & 0xfu;
  uart_putc(value < 10u ? (char)('0' + value) : (char)('a' + value - 10u));
}

int main(void) {
  for (uint32_t i = 0; i < 16u; i++) {
    led_write(i);
    put_hex_digit(i);
  }

  uart_putc('\n');
  while (!uart_tx_ready()) {
  }

  sim_halt(0);
}
