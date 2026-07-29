#ifndef LFE5UM5G_85F_EVN_BOARD_H
#define LFE5UM5G_85F_EVN_BOARD_H

#include <stdint.h>

#include "riscv_soc/mmio.h"

#define BOARD_LED_ADDR         0x10000000u
#define BOARD_UART_TX_ADDR     0x10001000u
#define BOARD_UART_STATUS_ADDR 0x10004000u

static inline void led_write(uint32_t value) {
  mmio_write32(BOARD_LED_ADDR, value);
}

static inline int uart_tx_ready(void) {
  return (int)(mmio_read32(BOARD_UART_STATUS_ADDR) & 1u);
}

static inline void uart_putc(char ch) {
  while (!uart_tx_ready()) {
  }
  mmio_write32(BOARD_UART_TX_ADDR, (uint32_t)(uint8_t)ch);
}

#endif
