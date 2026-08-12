// End-to-end simulated PLIC test.
//
// Build and run with:
//   RISCV_ARCH=rv32i_zicsr DESIGN=pipelined BOARD=sim
//   APP=examples/apps/plic_uart_irq_halt RUN_ARGS="+uart_rx=P +uart-bytes" make board-sim

#include <stdint.h>

#include "board.h"
#include "riscv_soc/csr.h"
#include "riscv_soc/plic.h"

extern void plic_irq_entry(void);

volatile uint32_t g_done;
volatile uint32_t g_error;
volatile uint32_t g_received;
volatile uint32_t g_claimed;

int main(void) {
  g_done = 0u;
  g_error = 0u;
  g_received = 0u;
  g_claimed = 0u;

  csr_disable_machine_interrupts();
  uart_set_rx_interrupt_enabled(0);
  plic_set_machine_enable(0u);
  plic_set_machine_threshold(0u);
  plic_set_priority(BOARD_PLIC_IRQ_UART, 1u);
  plic_enable_machine_source(BOARD_PLIC_IRQ_UART);

  csr_write_mtvec((uint32_t)(uintptr_t)plic_irq_entry);
  uart_set_rx_interrupt_enabled(1);
  csr_enable_machine_external_interrupt();

  while (!g_done) {
    __asm__ volatile("nop");
  }

  csr_disable_machine_external_interrupt();
  uart_set_rx_interrupt_enabled(0);

  if (g_error != 0u || g_claimed != BOARD_PLIC_IRQ_UART || g_received != (uint32_t)'P') {
    uart_putc('F');
    uart_putc('\n');
    halt(g_error != 0u ? g_error : 3u);
    return 1;
  }

  uart_putc('P');
  uart_putc('A');
  uart_putc('S');
  uart_putc('S');
  uart_putc('\n');
  halt(0u);
  return 0;
}
