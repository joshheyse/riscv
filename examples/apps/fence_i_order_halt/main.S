// fence_i_order_halt - verify self-modifying-code ordering through FENCE.I.

.section .text
.global _start

.equ ADDI_A0_ZERO_2, 0x00200513
.equ SIM_HALT_ADDR,  0x1000f000

_start:
  la    t0, patched_function
  jalr  ra, 0(t0)
  li    t1, 1
  bne   a0, t1, fail_initial

  // Rewrite the cached instruction through the data path. FENCE.I must make
  // that store visible before the next instruction fetch from the same PC.
  li    t1, ADDI_A0_ZERO_2
  sw    t1, 0(t0)
  fence.i

  jalr  ra, 0(t0)
  li    t1, 2
  bne   a0, t1, fail_updated

  li    a0, 0
  j     stop_sim

fail_initial:
  li    a0, 1
  j     stop_sim

fail_updated:
  li    a0, 2

stop_sim:
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  j     halt_loop

.align 2
patched_function:
  li    a0, 1
  ret
