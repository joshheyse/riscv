// mtvec_illegal_halt - exercise illegal-instruction trap entry and mret.
//
// Build/run with Zicsr enabled, for example:
//   just arch=rv32i_zicsr design=pipelined app=examples/apps/mtvec_illegal_halt board-sim
//
// Expected behavior:
//   1. write mtvec = trap_handler
//   2. execute an illegal instruction
//   3. enter trap_handler
//   4. handler advances mepc past the illegal instruction
//   5. mret returns to the normal path
//   6. halt simulation with code 0

.section .text
.global _start

.equ SIM_HALT_ADDR, 0x1000f000

_start:
  la   t0, trap_handler
  csrw mtvec, t0

  .word 0xffffffff

  addi a0, zero, 0
  jal  zero, stop_cpu

.align 2
trap_handler:
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret

stop_cpu:
  li   t0, SIM_HALT_ADDR
  sw   a0, 0(t0)

halt_loop:
  jal zero, halt_loop
