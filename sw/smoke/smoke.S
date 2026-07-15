# Minimal bare-metal smoke test: write 1 to `tohost`, which tells an
# HTIF-aware simulator (spike, sail) to exit with success.
.section .text.init
.globl _start

_start:
  li   t0, 1
  la   t1, tohost
  sd   t0, 0(t1)
1:
  j    1b

.section .tohost, "aw", @progbits
.align 6
.globl tohost
tohost:   .dword 0
.globl fromhost
fromhost: .dword 0
