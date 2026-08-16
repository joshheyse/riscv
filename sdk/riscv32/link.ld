OUTPUT_ARCH("riscv")
ENTRY(_start)

MEM_LENGTH = DEFINED(MemBytes) ? MemBytes : 4096;

MEMORY
{
  MEM (rwx) : ORIGIN = 0x00000000, LENGTH = MEM_LENGTH
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
    *(.srodata .srodata.*)
    *(.rodata .rodata.*)
  } > MEM

  .data : {
    *(.sdata .sdata.*)
    *(.data .data.*)
  } > MEM

  .init_array : {
    KEEP(*(.init_array .init_array.*))
  } > MEM

  .fini_array : {
    KEEP(*(.fini_array .fini_array.*))
  } > MEM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > MEM

  __stack_top = ORIGIN(MEM) + LENGTH(MEM);

  ASSERT(SIZEOF(.init_array) == 0, "global constructors are not supported yet")
  ASSERT(SIZEOF(.fini_array) == 0, "global destructors are not supported yet")
}
