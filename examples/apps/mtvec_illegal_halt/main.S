// mtvec_illegal_halt - exercise illegal-instruction trap entry through mtvec.
//
// Build/run with Zicsr enabled, for example:
//   just arch=rv32i_zicsr design=pipelined app=examples/apps/mtvec_illegal_halt board-sim
//
// Expected behavior once the core's trap controller observes the CSR-backed
// mtvec value:
//   1. write mtvec = trap_handler
//   2. execute an illegal instruction
//   3. enter trap_handler
//   4. halt simulation with code 0

.section .text
.global _start

.equ SIM_HALT_ADDR, 0x1000f000

_start:
  la   t0, trap_handler
  csrw mtvec, t0

  .word 0xffffffff

  addi a0, zero, 1
  jal  zero, stop_cpu

.align 2
trap_handler:
  addi a0, zero, 0
  jal  zero, stop_cpu

stop_cpu:
  li   t0, SIM_HALT_ADDR
  sw   a0, 0(t0)

halt_loop:
  jal zero, halt_loop
