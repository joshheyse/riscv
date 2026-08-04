#include "board.h"
#include "riscv_soc/csr.h"

static void put_result(uint32_t errors) {
  uart_putc(errors == 0u ? 'P' : 'F');
  uart_putc('\n');
}

int main(void) {
  uint32_t errors = 0;
  uint32_t saved_mstatus = csr_read_mstatus();

  if (csr_read_mvendorid() != 0u) {
    errors++;
  }
  if (csr_read_marchid() != 0u) {
    errors++;
  }
  if (csr_read_mimpid() != 0u) {
    errors++;
  }
  if (csr_read_mhartid() != 0u) {
    errors++;
  }

  csr_write_mstatus(0x00000088u);
  if (csr_read_mstatus() != 0x00000088u) {
    errors++;
  }

  csr_clear_mstatus(0x00000080u);
  if (csr_read_mstatus() != 0x00000008u) {
    errors++;
  }

  csr_set_mstatus(0x00000080u);
  if (csr_read_mstatus() != 0x00000088u) {
    errors++;
  }

  csr_write_mstatus(saved_mstatus);
  put_result(errors);

  while (!uart_tx_ready()) {
  }

  halt(errors);
  return 0;
}
