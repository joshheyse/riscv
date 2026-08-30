#ifndef RISCV_SOC_SAIL_COMPLIANCE_MODEL_H
#define RISCV_SOC_SAIL_COMPLIANCE_MODEL_H

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

#define RVMODEL_HALT                                               \
  li x1, 1;                                                       \
1: sw x1, tohost, t2;                                            \
  j 1b;

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
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif
