// clint_irq_client
//
// Demonstrates CLINT timer interrupt delivery with a "client callback" pattern:
//   - Program mtvec to a trap entry stub
//   - Enable machine timer interrupt
//   - Register a C callback as the timer event handler
//   - Service a few timer interrupts, then halt
//
// Build with:
//   RISCV_ARCH=rv32i_zicsr DESIGN=pipelined just board-sim top_sim app=examples/apps/clint_irq_client

#include <stdint.h>

#include "board.h"
#include "riscv_soc/csr.h"

typedef void (*timer_irq_cb_t)(void);

extern void clint_irq_entry(void);
extern void timer_irq_trampoline(void);

static volatile uint32_t g_timer_ticks;
static volatile uint32_t g_timer_done;
static volatile timer_irq_cb_t g_timer_cb;
static uint64_t g_next_mtimecmp;

static inline void clint_set_mtimecmp(uint64_t deadline) {
  mmio_write32(BOARD_CLINT_MTIMECMP_LO_ADDR, (uint32_t)(deadline & 0xffffffffu));
  mmio_write32(BOARD_CLINT_MTIMECMP_HI_ADDR, (uint32_t)(deadline >> 32));
}

void timer_irq_client(void) {
  g_timer_ticks++;
  uart_putc('T');
  uart_putc('0' + (uint8_t)(g_timer_ticks & 0x7u));

  if (g_timer_ticks >= 8u) {
    g_timer_done = 1u;
    return;
  }

  g_next_mtimecmp += 2000u;
  clint_set_mtimecmp(g_next_mtimecmp);
}

void timer_irq_trampoline(void) {
  timer_irq_cb_t cb = g_timer_cb;
  if (cb != 0) {
    cb();
  }
}

static void register_timer_callback(timer_irq_cb_t cb) {
  g_timer_cb = cb;
}

int main(void) {
  uint64_t now = timer_read_cycles();

  g_timer_ticks = 0u;
  g_timer_done = 0u;
  register_timer_callback(timer_irq_client);

  uart_putc('S');

  // Direct mode trap vector.
  csr_write_mtvec((uint32_t)(uintptr_t)clint_irq_entry);
  // Enable timer interrupt and global machine interrupt bit.
  csr_enable_machine_interrupts();

  // Program first timer deadline slightly in the future.
  g_next_mtimecmp = now + 8000u;
  clint_set_mtimecmp(g_next_mtimecmp);

  while (!g_timer_done) {
    __asm__ volatile("nop");
  }

  // Stop taking timer interrupts.
  csr_disable_machine_timer_interrupt();

  uart_putc('\n');
  uart_putc('D');
  uart_putc('O');
  uart_putc('N');
  uart_putc('E');
  uart_putc('\n');

  halt(0);
  return 0;
}
