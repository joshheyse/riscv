#ifndef RISCV_SOC_CSR_H
#define RISCV_SOC_CSR_H

#include <stdint.h>

#define MSTATUS_MIE  (1u << 3)
#define MSTATUS_MPIE (1u << 7)
#define MIE_MSIE     (1u << 3)
#define MIE_MTIE     (1u << 7)
#define MIE_MEIE     (1u << 11)
#define MIP_MSIP     (1u << 3)
#define MIP_MTIP     (1u << 7)
#define MIP_MEIP     (1u << 11)

// CSR instructions require building apps with `RISCV_ARCH=rv32i_zicsr`.

#define riscv_csr_read(csr)                                                    \
  ({                                                                           \
    uint32_t _value;                                                           \
    __asm__ volatile("csrr %0, " #csr : "=r"(_value));                         \
    _value;                                                                    \
  })

#define riscv_csr_write(csr, value)                                            \
  do {                                                                         \
    uint32_t _value = (uint32_t)(value);                                       \
    __asm__ volatile("csrw " #csr ", %0" : : "r"(_value));                     \
  } while (0)

#define riscv_csr_set(csr, mask)                                               \
  ({                                                                           \
    uint32_t _mask = (uint32_t)(mask);                                         \
    uint32_t _old;                                                             \
    __asm__ volatile("csrrs %0, " #csr ", %1" : "=r"(_old) : "r"(_mask));      \
    _old;                                                                      \
  })

#define riscv_csr_clear(csr, mask)                                             \
  ({                                                                           \
    uint32_t _mask = (uint32_t)(mask);                                         \
    uint32_t _old;                                                             \
    __asm__ volatile("csrrc %0, " #csr ", %1" : "=r"(_old) : "r"(_mask));      \
    _old;                                                                      \
  })

static inline uint32_t csr_read_mstatus(void) {
  return riscv_csr_read(mstatus);
}

static inline void csr_write_mstatus(uint32_t value) {
  riscv_csr_write(mstatus, value);
}

static inline uint32_t csr_set_mstatus(uint32_t mask) {
  return riscv_csr_set(mstatus, mask);
}

static inline uint32_t csr_clear_mstatus(uint32_t mask) {
  return riscv_csr_clear(mstatus, mask);
}

static inline uint32_t csr_read_mie(void) { return riscv_csr_read(mie); }

static inline void csr_write_mie(uint32_t value) {
  riscv_csr_write(mie, value);
}

static inline uint32_t csr_read_mip(void) { return riscv_csr_read(mip); }

static inline void csr_write_mip(uint32_t value) {
  riscv_csr_write(mip, value);
}

static inline void csr_enable_machine_interrupts(void) {
  riscv_csr_set(mstatus, MSTATUS_MIE);
  riscv_csr_set(mie, MIE_MTIE);
}

static inline void csr_disable_machine_timer_interrupt(void) {
  riscv_csr_clear(mie, MIE_MTIE);
}

static inline void csr_disable_machine_interrupts(void) {
  riscv_csr_clear(mstatus, MSTATUS_MIE);
}

static inline uint32_t csr_is_timer_interrupt_pending(void) {
  return (riscv_csr_read(mip) & MIP_MTIP);
}

static inline uint32_t csr_read_mtvec(void) { return riscv_csr_read(mtvec); }

static inline void csr_write_mtvec(uint32_t value) {
  riscv_csr_write(mtvec, value);
}

static inline uint32_t csr_read_mepc(void) { return riscv_csr_read(mepc); }

static inline void csr_write_mepc(uint32_t value) {
  riscv_csr_write(mepc, value);
}

static inline uint32_t csr_read_mcause(void) { return riscv_csr_read(mcause); }

static inline void csr_write_mcause(uint32_t value) {
  riscv_csr_write(mcause, value);
}

static inline uint32_t csr_read_mtval(void) { return riscv_csr_read(mtval); }

static inline void csr_write_mtval(uint32_t value) {
  riscv_csr_write(mtval, value);
}

static inline uint32_t csr_read_mvendorid(void) {
  return riscv_csr_read(mvendorid);
}

static inline uint32_t csr_read_marchid(void) {
  return riscv_csr_read(marchid);
}

static inline uint32_t csr_read_mimpid(void) { return riscv_csr_read(mimpid); }

static inline uint32_t csr_read_mhartid(void) {
  return riscv_csr_read(mhartid);
}

#endif
