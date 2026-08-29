// amo_satp_reservation_halt - verify that a legal SATP write clears LR/SC state.
//
// Build and run with the A and Zicsr extensions enabled:
//   make board-sim BOARD=sim BOARD_SIM=top_sim \
//     APP=examples/apps/amo_satp_reservation_halt RISCV_ARCH=rv32ima_zicsr
//
// The successful LR/SC pair is a baseline: without it, a core whose SC always
// fails could incorrectly pass the SATP invalidation check.

.section .text
.global _start

.equ SIM_HALT_ADDR, 0x1000f000

_start:
  la    t0, test_word

  // Baseline: a matching SC succeeds, returns zero, and updates memory.
  lr.w  t1, (t0)
  li    t2, 0x12345678
  sc.w  t3, t2, (t0)
  bnez  t3, fail_baseline_sc
  lw    t4, 0(t0)
  bne   t4, t2, fail_baseline_value

  // A legal SATP write must invalidate an otherwise matching reservation.
  li    t2, 0xaaaaaaaa
  sw    t2, 0(t0)
  lr.w  t1, (t0)
  csrw  satp, zero
  li    t2, 0x55555555
  sc.w  t3, t2, (t0)
  li    t4, 1
  bne   t3, t4, fail_satp_sc

  // A failed SC must leave the reserved word unchanged.
  lw    t4, 0(t0)
  li    t5, 0xaaaaaaaa
  bne   t4, t5, fail_satp_value

  li    a0, 0
  j     stop_sim

fail_baseline_sc:
  li    a0, 1
  j     stop_sim

fail_baseline_value:
  li    a0, 2
  j     stop_sim

fail_satp_sc:
  li    a0, 3
  j     stop_sim

fail_satp_value:
  li    a0, 4

stop_sim:
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  j     halt_loop

.section .data
.align 2
test_word:
  .word 0x0badc0de
