.section .text
.global _start
_start:
  addi x1, x0, 5
  addi x2, x0, 3
  add  x3, x1, x2
  sub  x4, x1, x2
  sll  x5, x1, x2
  slt  x6, x2, x1
  sltu x7, x2, x1
  xor  x8, x1, x2
  srl  x9, x5, x2
  addi x10, x0, -8
  sra  x11, x10, x2
  or   x12, x1, x2
  and  x13, x1, x2

  slti  x14, x10, -4
  sltiu x15, x10, 1
  xori  x16, x1, 7
  ori   x17, x1, 8
  andi  x18, x1, 6
  slli  x19, x1, 2
  srli  x20, x10, 1
  srai  x21, x10, 1

  lui   x22, 0x12345
  auipc x23, 0

  addi x24, x0, -1
  sw   x24, 0(x0)
  addi x25, x0, 127
  sb   x25, 1(x0)
  lb   x26, 2(x0)
  lbu  x27, 1(x0)
  lui  x28, 0x8
  addi x28, x28, 1
  sh   x28, 2(x0)
  lh   x29, 2(x0)
  lhu  x30, 2(x0)
  lw   x5, 0(x0)

  fence

  beq  x1, x1, 1f
  addi x31, x0, 1
  jal  x0, done
1:
  bne  x1, x2, 2f
  addi x31, x0, 2
  jal  x0, done
2:
  blt  x2, x1, 3f
  addi x31, x0, 3
  jal  x0, done
3:
  bge  x1, x2, 4f
  addi x31, x0, 4
  jal  x0, done
4:
  bltu x2, x1, 5f
  addi x31, x0, 5
  jal  x0, done
5:
  bgeu x1, x2, 6f
  addi x31, x0, 6
  jal  x0, done
6:
  jal  x6, jal_target
  addi x31, x0, 7
  jal  x0, done

jal_target:
  addi x8, x0, 0xf5
  jalr x9, 0(x8)
  addi x31, x0, 8
  jal  x0, done

jalr_target:
  addi x10, x0, 42

done:
  sw   x31, 4(x0)
  sw   x9, 8(x0)
  sw   x10, 12(x0)
loop:
  jal  x0, loop
