OUTPUT_ARCH("riscv")
ENTRY(_start)

IMEM_LENGTH = DEFINED(ImemBytes) ? ImemBytes : 2048;
DMEM_LENGTH = DEFINED(DmemBytes) ? DmemBytes : 2048;

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = IMEM_LENGTH
  DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = DMEM_LENGTH
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
    *(.srodata .srodata.*)
    *(.rodata .rodata.*)
  } > IMEM

  .data : {
    *(.sdata .sdata.*)
    *(.data .data.*)
  } > DMEM

  .init_array : {
    KEEP(*(.init_array .init_array.*))
  } > IMEM

  .fini_array : {
    KEEP(*(.fini_array .fini_array.*))
  } > IMEM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DMEM

  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

  ASSERT(SIZEOF(.data) == 0, "initialized .data is not supported yet; use const/immediates or add a dmem image")
  ASSERT(SIZEOF(.init_array) == 0, "global constructors are not supported yet")
  ASSERT(SIZEOF(.fini_array) == 0, "global destructors are not supported yet")
}
