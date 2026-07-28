#ifndef RISCV_SOC_SIM_H
#define RISCV_SOC_SIM_H

#include <stdint.h>

#include "riscv_soc/mmio.h"

#ifndef RISCV_SOC_SIM_HALT_ADDR
#define RISCV_SOC_SIM_HALT_ADDR 0x1000f000u
#endif

static inline void sim_halt(uint32_t code) {
  mmio_write32(RISCV_SOC_SIM_HALT_ADDR, code);
}

#endif
