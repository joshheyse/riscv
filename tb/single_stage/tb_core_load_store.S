.section .text
.global _start
_start:
  addi x1, x0, 0
  addi x2, x0, -1
  sw   x2, 0(x1)
  addi x3, x0, 127
  sb   x3, 1(x1)
  lb   x4, 1(x1)
  lb   x5, 2(x1)
  lbu  x6, 2(x1)
  lui  x7, 0x8
  addi x7, x7, 1
  sh   x7, 2(x1)
  lh   x8, 2(x1)
  lhu  x9, 2(x1)
  lw   x10, 0(x1)
  sw   x10, 4(x1)
loop:
  jal  x0, loop
