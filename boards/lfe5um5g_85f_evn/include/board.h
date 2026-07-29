#ifndef LFE5UM5G_85F_EVN_BOARD_H
#define LFE5UM5G_85F_EVN_BOARD_H

#include <stdint.h>

#include "board_memmap.h"
#include "riscv_soc/mmio.h"

#define BOARD_TIMER_CYCLES_PER_US (BOARD_TIMER_HZ / 1000000u)
#define BOARD_TIMER_CYCLES_PER_MS (BOARD_TIMER_HZ / 1000u)

static inline void led_write(uint32_t value) {
  mmio_write32(BOARD_LED_ADDR, value);
}

static inline int dip_switch_read(uint8_t value) {
  return (int)(mmio_read32(BOARD_DIP_SWITCH_ADDR) & (1u << value));
}

static inline int uart_tx_ready(void) {
  return (int)(mmio_read32(BOARD_UART_STATUS_ADDR) & 1u);
}

static inline void uart_putc(char ch) {
  while (!uart_tx_ready()) {
  }
  mmio_write32(BOARD_UART_TX_ADDR, (uint32_t)(uint8_t)ch);
}

static inline uint64_t timer_read_cycles(void) {
  uint64_t hi = (uint64_t)mmio_read32(BOARD_TIMER_HI_ADDR);
  uint64_t lo = (uint64_t)mmio_read32(BOARD_TIMER_LO_ADDR);
  uint64_t next_hi = (uint64_t)mmio_read32(BOARD_TIMER_HI_ADDR);
  if (hi != next_hi) {
    hi = next_hi;
    lo = (uint64_t)mmio_read32(BOARD_TIMER_LO_ADDR);
  }
  return (hi << 32) | lo;
}

static inline void timer_sleep_cycles(uint64_t cycles) {
  uint64_t start = timer_read_cycles();
  while ((timer_read_cycles() - start) < cycles)
    ;
}

static inline void sleep_us(uint64_t us) {
  while (us--) {
    timer_sleep_cycles(BOARD_TIMER_CYCLES_PER_US);
  }
}

static inline void sleep_ms(uint64_t ms) {
  while (ms--) {
    timer_sleep_cycles(BOARD_TIMER_CYCLES_PER_MS);
  }
}

static inline void sleep_s(uint64_t s) {
  while (s--) {
    timer_sleep_cycles(BOARD_TIMER_HZ);
  }
}

static inline void gpio_set(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }

  mmio_write32(BOARD_GPIO_SET_ADDR, 1u << pin);
}

static inline void gpio_clear(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_CLEAR_ADDR, 1u << pin);
}

static inline void gpio_toggle(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_TOGGLE_ADDR, 1u << pin);
}

static inline int gpio_read(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return -1;
  }
  return (int)((mmio_read32(BOARD_GPIO_DATA_IN_ADDR) >> pin) & 1u);
}

static inline void gpio_set_output(uint32_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_DIR_ADDR,
               mmio_read32(BOARD_GPIO_DIR_ADDR) | (1u << pin));
}

static inline void gpio_set_input(uint32_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_DIR_ADDR,
               mmio_read32(BOARD_GPIO_DIR_ADDR) & ~(1u << pin));
}

#endif
