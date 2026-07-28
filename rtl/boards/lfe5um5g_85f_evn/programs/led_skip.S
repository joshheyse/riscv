.section .text
.global _start
_start:
  lui  x1, 0x10000
  addi x2, x0, 1

loop:
  sw   x2, 0(x1)

  slli x2, x2, 1
  andi x2, x2, 0xff
  bne  x2, x0, keep
  addi x2, x0, 1

keep:
  lui x3, 0x5B9
  addi x3, x3, -640

delay:
  addi x3, x3, -2
  bne  x3, x0, delay

  jal  x0, loop


#.section .text
#.global _start
#_start:
#  lui  x1, 0x10000
#  addi x2, x0, 1
#loop:
#  sw   x2, 0(x1)
#
#  slli x2, x2, 1
#  andi x2, x2, 0xff
#  bne  x2, x0, keep
#  addi x2, x0, 1
#keep:
#  lui  x3, 0x5B9
#  addi x3, x3, -640
#delay:
#  addi x3, x3, -1
#  bne  x3, x0, delay
#  jal  x0, loop



