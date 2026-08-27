// End-to-end SBI-style timer delivery test.
//
// S-mode requests an absolute deadline with an ECALL. The M-mode handler
// programs mtimecmp, converts the resulting MTIP into STIP, and returns. The
// delegated supervisor timer handler then asks M-mode to disarm the timer and
// clear STIP before reporting success to top_sim.

.section .text
.global _start

.equ MSTATUS_MPP_S_SIE, 0x00000802
.equ MIE_MTIE_STIE,     0x000000a0
.equ MIDELEG_STIP,      0x00000020
.equ MCOUNTEREN_TM,     0x00000002
.equ MIP_STIP,          0x00000020

.equ MCAUSE_INTERRUPT,  0x80000000
.equ MCAUSE_MTIP,       7
.equ MCAUSE_ECALL_S,    9

.equ CLINT_MTIMECMP_LO, 0x10002010
.equ CLINT_MTIMECMP_HI, 0x10002014
.equ SIM_HALT_ADDR,     0x1000f000

_start:
  la    t0, machine_trap
  csrw  mtvec, t0
  la    t0, supervisor_trap
  csrw  stvec, t0

  li    t0, MIDELEG_STIP
  csrw  mideleg, t0
  li    t0, MIE_MTIE_STIE
  csrw  mie, t0
  li    t0, MCOUNTEREN_TM
  csrw  mcounteren, t0

  la    t0, supervisor_entry
  csrw  mepc, t0
  li    t0, MSTATUS_MPP_S_SIE
  csrw  mstatus, t0
  mret

supervisor_entry:
  // SBI TIME set_timer convention on RV32: a0/a1 hold the absolute 64-bit
  // deadline, a6 is function 0, and a7 identifies the TIME extension.
  csrr  a0, time
  li    t0, 500
  add   a0, a0, t0
  sltu  a1, a0, t0
  li    a6, 0
  li    a7, 0x54494d45
  ecall

supervisor_wait:
  j     supervisor_wait

machine_trap:
  csrr  t0, mcause
  li    t1, MCAUSE_ECALL_S
  beq   t0, t1, machine_set_timer
  li    t1, MCAUSE_INTERRUPT + MCAUSE_MTIP
  beq   t0, t1, machine_timer_interrupt
  j     fail

machine_set_timer:
  // Clear a previously injected supervisor timer interrupt. Writing the low
  // half to all ones first prevents an RV32 half-write from transiently making
  // the new compare value earlier than mtime.
  li    t0, MIP_STIP
  csrc  mip, t0
  li    t0, CLINT_MTIMECMP_LO
  li    t1, -1
  sw    t1, 0(t0)
  li    t0, CLINT_MTIMECMP_HI
  sw    a1, 0(t0)
  li    t0, CLINT_MTIMECMP_LO
  sw    a0, 0(t0)

  csrr  t0, mepc
  addi  t0, t0, 4
  csrw  mepc, t0
  li    a0, 0
  li    a1, 0
  mret

machine_timer_interrupt:
  // Disable MTIP before injecting STIP so the machine interrupt cannot
  // immediately retrigger after mret.
  li    t0, CLINT_MTIMECMP_HI
  li    t1, -1
  sw    t1, 0(t0)
  li    t0, CLINT_MTIMECMP_LO
  sw    t1, 0(t0)
  li    t0, MIP_STIP
  csrs  mip, t0
  mret

supervisor_trap:
  csrr  t0, scause
  li    t1, MCAUSE_INTERRUPT + 5
  bne   t0, t1, fail

  // Use the same SBI-style call to clear STIP and leave mtimecmp disabled.
  li    a0, -1
  li    a1, -1
  li    a6, 0
  li    a7, 0x54494d45
  ecall

  li    a0, 0
  j     stop_sim

fail:
  li    a0, 1

stop_sim:
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  j     halt_loop
