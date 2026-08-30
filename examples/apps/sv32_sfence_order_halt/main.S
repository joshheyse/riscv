// sv32_sfence_order_halt - verify page-table-store ordering through SFENCE.VMA.
//
// The first call through virtual address 0x00400000 reaches physical page 2.
// Supervisor code then rewrites that leaf PTE through the D-cache, executes a
// selective SFENCE.VMA, and calls the same virtual address again. The second
// call must reach physical page 3, proving that the dirty PTE became visible to
// the instruction walker and that stale I-cache/TLB state was discarded.
//
//   make board-sim BOARD=sim APP=examples/apps/sv32_sfence_order_halt \
//     RISCV_ARCH=rv32i_zicsr MEM_BYTES=131072

.section .text.init
.global _start

.equ MSTATUS_MPP_SUPERVISOR, 0x00000800
.equ SATP_SV32_ROOT,          0x80000010
.equ ALIAS_VIRTUAL_ADDR,      0x00400000
.equ ALIAS_LEAF_PTE_ADDR,     0x00012000
.equ PAGE_3_EXECUTE_PTE,      0x00000ccb
.equ SIM_HALT_ADDR,           0x1000f000
.equ PTE_RWXAD_FLAGS,         0x000000cf
.equ PTE_RXAD_FLAGS,          0x000000cb
.equ PTE_RWAD_FLAGS,          0x000000c7

_start:
  li    t0, -1
  csrw  pmpaddr0, t0
  li    t0, 0x1f
  csrw  pmpcfg0, t0

  la    t0, supervisor_entry
  csrw  mepc, t0
  li    t0, MSTATUS_MPP_SUPERVISOR
  csrw  mstatus, t0
  li    t0, SATP_SV32_ROOT
  csrw  satp, t0
  sfence.vma zero, zero
  mret

supervisor_entry:
  li    t0, ALIAS_VIRTUAL_ADDR
  jalr  ra, 0(t0)
  li    t1, 1
  bne   a0, t1, fail_first_mapping

  // This store remains dirty in D-cache until SFENCE.VMA orders it before the
  // subsequent implicit instruction-side page-table reads.
  li    t0, ALIAS_LEAF_PTE_ADDR
  li    t1, PAGE_3_EXECUTE_PTE
  sw    t1, 0(t0)
  li    t0, ALIAS_VIRTUAL_ADDR
  sfence.vma t0, zero

  li    t0, ALIAS_VIRTUAL_ADDR
  jalr  ra, 0(t0)
  li    t1, 2
  bne   a0, t1, fail_second_mapping

  li    a0, 0
  jal   zero, report

fail_first_mapping:
  li    a0, 1
  jal   zero, report

fail_second_mapping:
  li    a0, 2

report:
  li    t0, SIM_HALT_ADDR
  sw    a0, 0(t0)

halt_loop:
  jal   zero, halt_loop

.org 0x00002000
physical_page_2:
  li    a0, 1
  ret

.org 0x00003000
physical_page_3:
  li    a0, 2
  ret

// Root page table at physical 0x10000:
// - VPN[1] 0 points at the low identity table.
// - VPN[1] 1 points at the remappable alias table.
// - VPN[1] 0x40 maps simulator MMIO as a 4 MiB identity leaf.
.org 0x00010000
root_page_table:
  .word (0x11 << 10) | 0x1
  .word (0x12 << 10) | 0x1
  .zero 62 * 4
  .word (0x10000000 >> 12 << 10) | PTE_RWAD_FLAGS
  .zero (1024 - 65) * 4

// Identity-map the low 128 KiB, including the page tables themselves.
.org 0x00011000
low_page_table:
  .set identity_leaf_pte, PTE_RWXAD_FLAGS
  .rept 32
    .word identity_leaf_pte
    .set identity_leaf_pte, identity_leaf_pte + 0x400
  .endr
  .zero (1024 - 32) * 4

// Initially map the alias to physical page 2. Supervisor code rewrites this
// entry to PAGE_3_EXECUTE_PTE before the selective fence.
.org 0x00012000
alias_page_table:
  .word (2 << 10) | PTE_RXAD_FLAGS
  .zero (1024 - 1) * 4
