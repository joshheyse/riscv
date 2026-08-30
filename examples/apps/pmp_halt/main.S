// pmp_halt - verify PMP enforcement and load-access-fault trap metadata.

.section .text
.global _start

.equ PMP_CODE_TOP,       0x00000400  // TOR address encoding for byte address 0x1000
.equ PMPCFG_TOR_RX,      0x0000000d
.equ DENIED_LOAD_ADDR,   0x00002000
.equ CAUSE_LOAD_ACCESS,  5
.equ SIM_HALT_ADDR,      0x1000f000

_start:
  la    t0, machine_trap
  csrw  mtvec, t0

  li    t0, PMP_CODE_TOP
  csrw  pmpaddr0, t0
  li    t0, PMPCFG_TOR_RX
  csrw  pmpcfg0, t0

  la    t0, user_entry
  csrw  mepc, t0
  csrw  mstatus, zero
  mret

user_entry:
  // The instruction fetch is permitted by entry 0, but this load has no
  // matching PMP region and must trap before reaching physical memory.
  li    t0, DENIED_LOAD_ADDR
  lw    t1, 0(t0)
  li    a0, 1
  j     stop_sim

machine_trap:
  csrr  t0, mcause
  li    t1, CAUSE_LOAD_ACCESS
  bne   t0, t1, fail_cause
  csrr  t0, mtval
  li    t1, DENIED_LOAD_ADDR
  bne   t0, t1, fail_tval
  li    a0, 0
  j     stop_sim

fail_cause:
  li    a0, 2
  j     stop_sim

fail_tval:
  li    a0, 3

stop_sim:
  // Machine mode bypasses the unlocked PMP entry.
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  j     halt_loop
