#ifndef RISCV_SOC_PLIC_H
#define RISCV_SOC_PLIC_H

#include <stdint.h>

#include "board_constants.h"
#include "riscv_soc/mmio.h"

static inline void plic_set_priority(uint32_t source_id, uint32_t priority) {
  mmio_write32(BOARD_PLIC_PRIORITY_BASE_ADDR + (source_id * 4u), priority);
}

static inline uint32_t plic_get_priority(uint32_t source_id) {
  return mmio_read32(BOARD_PLIC_PRIORITY_BASE_ADDR + (source_id * 4u));
}

static inline uint32_t plic_pending(void) {
  return mmio_read32(BOARD_PLIC_PENDING_ADDR);
}

static inline void plic_set_machine_enable(uint32_t enable_mask) {
  mmio_write32(BOARD_PLIC_M_ENABLE_ADDR, enable_mask);
}

static inline uint32_t plic_get_machine_enable(void) {
  return mmio_read32(BOARD_PLIC_M_ENABLE_ADDR);
}

static inline void plic_enable_machine_source(uint32_t source_id) {
  plic_set_machine_enable(plic_get_machine_enable() | (1u << source_id));
}

static inline void plic_disable_machine_source(uint32_t source_id) {
  plic_set_machine_enable(plic_get_machine_enable() & ~(1u << source_id));
}

static inline void plic_set_machine_threshold(uint32_t threshold) {
  mmio_write32(BOARD_PLIC_M_THRESHOLD_ADDR, threshold);
}

static inline uint32_t plic_get_machine_threshold(void) {
  return mmio_read32(BOARD_PLIC_M_THRESHOLD_ADDR);
}

static inline uint32_t plic_claim_machine(void) {
  return mmio_read32(BOARD_PLIC_M_CLAIM_COMPLETE_ADDR);
}

static inline void plic_complete_machine(uint32_t source_id) {
  mmio_write32(BOARD_PLIC_M_CLAIM_COMPLETE_ADDR, source_id);
}

#endif
