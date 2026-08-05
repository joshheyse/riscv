// mtvec_ebreak_mret_halt - exercise ebreak trap entry and mret.
//
// Build/run with Zicsr enabled, for example:
//   just arch=rv32i_zicsr design=pipelined app=examples/apps/mtvec_ebreak_mret_halt board-sim
//
// Expected behavior:
//   1. write mtvec = trap_handler
//   2. set failure code in a0
//   3. execute ebreak after the failure code has time to commit
//   4. handler changes a0 to success, advances mepc, and mret returns
//   5. halt simulation with code 0

.section .text
.global _start

.equ SIM_HALT_ADDR, 0x1000f000

_start:
  la   t0, trap_handler
  csrw mtvec, t0

  addi a0, zero, 1
  nop
  nop
  ebreak
  nop
  nop
  jal  zero, stop_cpu

.align 2
trap_handler:
  addi a0, zero, 0
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret

stop_cpu:
  li   t0, SIM_HALT_ADDR
  sw   a0, 0(t0)

halt_loop:
  jal zero, halt_loop
