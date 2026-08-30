#ifndef RISCV_SOC_COMPLIANCE_MODEL_H
#define RISCV_SOC_COMPLIANCE_MODEL_H

#define RVMODEL_PMP_GRAIN 0
#define RVMODEL_NUM_PMPS 16
// This RV32 core has IALIGN=32 and does not implement C. The suite's default
// alignment uses 16-bit C.NOP padding, so keep executable alignment at 4 bytes.
#define UNROLLSZ 2
// This core permits zero in mtval for software breakpoints. Keep all other
// suite-default relative-tval checks enabled.
#define SET_REL_TVAL_MSK 0x0000b0f3

#define RVMODEL_DATA_SECTION                                      \
  .pushsection .tohost,"aw",@progbits;                            \
  .align 3; .global tohost; tohost: .dword 0;                     \
  .align 3; .global fromhost; fromhost: .dword 0;                 \
  .popsection;                                                    \
  .align 3; .global begin_regstate; begin_regstate: .word 128;    \
  .align 3; .global end_regstate; end_regstate: .word 4;

// The FENCE.I encoding cleans the data cache and invalidates the instruction
// cache in this core, making the completed signature visible to the harness.
// Use the encoding so tests that do not advertise Zifencei still assemble;
// this instruction belongs to the model epilogue, not to the test under audit.
#define RVMODEL_HALT                                               \
  .word 0x0000100f;                                               \
  li t0, 0x1000f000;                                             \
  sw zero, 0(t0);                                                \
1: j 1b;

#define RVMODEL_BOOT

#define RVMODEL_DATA_BEGIN                                        \
  RVMODEL_DATA_SECTION                                           \
  .align 2;                                                      \
  .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                          \
  .align 2; .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT                                       \
  li t1, 1;                                                      \
  li t2, 0x10002008;                                             \
  sw t1, 0(t2);

#define RVMODEL_CLEAR_MSW_INT                                     \
  li t2, 0x10002008;                                             \
  sw zero, 0(t2);

#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif
