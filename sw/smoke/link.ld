/* Bare-metal layout for spike/sail: RAM starts at 0x80000000. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .tohost ALIGN(0x1000) : { *(.tohost) }
  .text : { *(.text) }
  .data : { *(.data) }
  .bss  : { *(.bss)  }
}
