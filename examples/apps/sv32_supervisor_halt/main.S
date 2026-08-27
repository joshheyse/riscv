// sv32_supervisor_halt - enter Supervisor mode and execute through Sv32.
//
// Build with 8 KiB of simulated RAM so the root page table at 0x1000 exists:
//   make board-sim BOARD=sim BOARD_SIM=top_sim \
//     APP=examples/apps/sv32_supervisor_halt RISCV_ARCH=rv32i_zicsr MEM_BYTES=8192
//
// The root table uses two 4 MiB leaf mappings:
// - virtual 0x00000000 -> physical 0x00000000, RWX for program and test data
// - virtual 0x10000000 -> physical 0x10000000, RW for simulator MMIO

.section .text
.global _start

.equ MSTATUS_MPP_SUPERVISOR, 0x00000800
.equ SATP_SV32_ROOT_PPN_1,    0x80000001
.equ TEST_DATA_ADDR,          0x00000800
.equ TEST_VALUE,              0x51a7c0de
.equ SIM_HALT_ADDR,           0x1000f000

_start:
  // Return from Machine mode into the identity-mapped Supervisor entry point.
  la    t0, supervisor_entry
  csrw  mepc, t0
  li    t0, MSTATUS_MPP_SUPERVISOR
  csrw  mstatus, t0

  // Root page table is physically located at 0x1000 (PPN 1).
  li    t0, SATP_SV32_ROOT_PPN_1
  csrw  satp, t0
  sfence.vma zero, zero
  mret

supervisor_entry:
  // Exercise a translated store and load in Supervisor mode.
  li    t0, TEST_DATA_ADDR
  li    t1, TEST_VALUE
  sw    t1, 0(t0)
  lw    t2, 0(t0)
  bne   t1, t2, fail

  li    a0, 0
  jal   zero, stop_sim

fail:
  li    a0, 1

stop_sim:
  // This store is translated through the second superpage mapping.
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  jal   zero, halt_loop

// Sv32 root page table at physical address 0x1000.
// Flags: V=1, R=1, W=1, X as noted, A=1, D=1, U=0.
.org 0x1000
root_page_table:
  .word 0x000000cf  // VPN[1]=0x000: low 4 MiB, identity mapped RWX
  .zero 63 * 4
  .word 0x040000c7  // VPN[1]=0x040: 0x10000000 MMIO, identity mapped RW
