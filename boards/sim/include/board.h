#ifndef SIM_BOARD_H
#define SIM_BOARD_H

#define RISCV_SOC_BOARD_CUSTOM_HALT
#include "riscv_soc/board.h"

static inline void halt(uint32_t code) {
  mmio_write32(BOARD_SIM_HALT_ADDR, code);
}

#endif
