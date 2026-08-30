// sv32_tlb_stress - fixed-work Sv32 translation benchmark.
//
// Run both configurations with:
//   make board-sim BOARD=sim APP=examples/apps/sv32_tlb_stress \
//     RISCV_ARCH=rv32i_zicsr MEM_BYTES=131072 TLB_ENABLED=1
//   make board-sim BOARD=sim APP=examples/apps/sv32_tlb_stress \
//     RISCV_ARCH=rv32i_zicsr MEM_BYTES=131072 TLB_ENABLED=0
//
// The simulator halt code is the measured mcycle delta. The workload keeps its
// instruction loop in one page and repeatedly touches twelve distinct 4 KiB
// data pages. Each word uses a different cache-set offset, avoiding an
// artificial same-set L1 conflict while keeping all translations hot in the
// 16-entry DTLB.

.section .text.init
.global _start

.equ ROOT_PAGE_TABLE,        0x00010000
.equ LEVEL_0_PAGE_TABLE,     0x00011000
.equ DATA_BASE,              0x00004000
.equ DATA_STRIDE,            0x00001020
.equ DATA_PAGES,             12
.equ WARMUP_PASSES,          4
.equ MEASURED_PASSES,        128
.equ SIM_HALT_ADDR,          0x1000f000

.equ MSTATUS_MPP_SUPERVISOR, 0x00000800
.equ MCOUNTEREN_CY,           0x00000001
.equ SATP_SV32_ROOT,          0x80000010
.equ PTE_RWXAD_FLAGS,         0x000000cf
.equ PTE_RWAD_FLAGS,          0x000000c7

_start:
  li    t0, -1
  csrw  pmpaddr0, t0
  li    t0, 0x1f
  csrw  pmpcfg0, t0

  // Seed the twelve benchmark words while translation is still bypassed. The
  // page tables themselves are initialized directly in the program image.
  li    t0, DATA_BASE
  li    t1, DATA_STRIDE
  li    t2, DATA_PAGES
  li    t3, 0x13579bdf
seed_data:
  sw    t3, 0(t0)
  add   t0, t0, t1
  addi  t3, t3, 17
  addi  t2, t2, -1
  bnez  t2, seed_data

  la    t0, supervisor_entry
  csrw  mepc, t0
  li    t0, MSTATUS_MPP_SUPERVISOR
  csrw  mstatus, t0
  li    t0, MCOUNTEREN_CY
  csrw  mcounteren, t0
  li    t0, SATP_SV32_ROOT
  csrw  satp, t0
  sfence.vma zero, zero
  mret

supervisor_entry:
  li    s0, DATA_BASE
  li    s1, DATA_STRIDE
  li    s2, DATA_PAGES
  li    s3, 0

  // Populate the instruction and data TLBs before the measured region.
  li    t0, WARMUP_PASSES
warmup_outer:
  mv    t1, s0
  mv    t2, s2
warmup_inner:
  lw    t3, 0(t1)
  xor   t3, t3, t0
  addi  t3, t3, 1
  sw    t3, 0(t1)
  add   t1, t1, s1
  addi  t2, t2, -1
  bnez  t2, warmup_inner
  addi  t0, t0, -1
  bnez  t0, warmup_outer

  csrr  s4, cycle
  li    t0, MEASURED_PASSES
measure_outer:
  mv    t1, s0
  mv    t2, s2
measure_inner:
  lw    t3, 0(t1)
  slli  t4, t3, 1
  srli  t3, t3, 31
  or    t3, t3, t4
  xor   t3, t3, t0
  add   t3, t3, t2
  sw    t3, 0(t1)
  add   s3, s3, t3
  add   t1, t1, s1
  addi  t2, t2, -1
  bnez  t2, measure_inner
  addi  t0, t0, -1
  bnez  t0, measure_outer
  csrr  s5, cycle

  sub   a0, s5, s4
  bnez  s3, report
  li    a0, -1  // Reserve all-ones as a checksum-failure result.

report:
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  jal   zero, halt_loop

// Root table at physical 0x10000. Entry 0 points at the level-0 table; entry
// 0x40 maps simulator MMIO as an identity-mapped 4 MiB leaf.
.org ROOT_PAGE_TABLE
root_page_table:
  .word (0x11 << 10) | 0x1
  .zero 63 * 4
  .word (0x10000000 >> 12 << 10) | PTE_RWAD_FLAGS
  .zero (1024 - 65) * 4

// Identity-map the low 128 KiB as 32 ordinary 4 KiB pages. The benchmark,
// page tables, and machine-to-supervisor transition all live in this range.
.org LEVEL_0_PAGE_TABLE
level_0_page_table:
  .set leaf_pte, PTE_RWXAD_FLAGS
  .rept 32
    .word leaf_pte
    .set leaf_pte, leaf_pte + 0x400
  .endr
  .zero (1024 - 32) * 4
