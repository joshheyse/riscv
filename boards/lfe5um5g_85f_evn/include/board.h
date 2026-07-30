#ifndef LFE5UM5G_85F_EVN_BOARD_H
#define LFE5UM5G_85F_EVN_BOARD_H

#include <stdint.h>

#include "board_memmap.h"
#include "riscv_soc/mmio.h"

#define BOARD_TIMER_CYCLES_PER_US (BOARD_TIMER_HZ / 1000000u)
#define BOARD_TIMER_CYCLES_PER_MS (BOARD_TIMER_HZ / 1000u)

static inline void led_write(uint32_t led) {
  mmio_write32(BOARD_LED_ADDR, led);
}

static inline int dip_switch_read(uint8_t dip) {
  if (BOARD_NUM_DIP_SWITCHES <= dip) {
    return -1;
  }
  return (int)((mmio_read32(BOARD_DIP_SWITCH_ADDR) >> dip) & 1u);
}

static inline int push_button_read(uint8_t button) {
  if (BOARD_NUM_PUSH_BUTTONS <= button) {
    return -1;
  }
  return (int)((mmio_read32(BOARD_PUSH_BUTTON_ADDR) >> button) & 1u);
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

static inline void gpio_set_output(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_DIR_ADDR,
               mmio_read32(BOARD_GPIO_DIR_ADDR) | (1u << pin));
}

static inline void gpio_set_input(uint16_t pin) {
  if (BOARD_NUM_GPIO <= pin) {
    return;
  }
  mmio_write32(BOARD_GPIO_DIR_ADDR,
               mmio_read32(BOARD_GPIO_DIR_ADDR) & ~(1u << pin));
}

static inline int spi_busy(void) {
  return (int)(mmio_read32(BOARD_SPI_STATUS_ADDR) & 1u);
}

static inline uint8_t spi_transfer(uint8_t data) {
  while (spi_busy())
    ;
  mmio_write32(BOARD_SPI_DATA_ADDR, (uint32_t)data);
  mmio_write32(BOARD_SPI_CONTROL_ADDR, (uint32_t)1);
  while (spi_busy())
    ;
  return (uint8_t)(mmio_read32(BOARD_SPI_DATA_ADDR) & 0xffu);
}

static inline int i2c_busy(void) {
  return (int)(mmio_read32(BOARD_I2C_STATUS_ADDR) & 1u);
}

static inline int i2c_write_byte(uint8_t addr7, uint8_t data) {
  while (i2c_busy())
    ;
  mmio_write32(BOARD_I2C_ADDRESS_ADDR, (uint32_t)addr7);
  mmio_write32(BOARD_I2C_DATA_ADDR, (uint32_t)data);
  mmio_write32(BOARD_I2C_CONTROL_ADDR, (uint32_t)1);
  while (i2c_busy())
    ;
  return (mmio_read32(BOARD_I2C_STATUS_ADDR) & 2u) ? -1 : 0;
}

#endif
