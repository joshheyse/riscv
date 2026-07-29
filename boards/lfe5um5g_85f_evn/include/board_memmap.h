/* Generated from boards/lfe5um5g_85f_evn/memmap.yml. Do not edit. */
#ifndef LFE5UM5G_85F_EVN_MEMMAP_H
#define LFE5UM5G_85F_EVN_MEMMAP_H

#define BOARD_DMEM_BASE          0x00000000u
#define BOARD_DMEM_SIZE          0x00000800u
#define BOARD_LED_ADDR           0x10000000u
#define BOARD_UART_TX_ADDR       0x10001000u
#define BOARD_UART_STATUS_ADDR   0x10004000u
#define BOARD_SIM_HALT_ADDR      0x1000f000u
#define BOARD_TIMER_LO_ADDR      0x10002000u
#define BOARD_TIMER_HI_ADDR      0x10002004u
#define BOARD_TIMER_HZ           0x00b71b00u

#ifndef RISCV_SOC_SIM_HALT_ADDR
#define RISCV_SOC_SIM_HALT_ADDR BOARD_SIM_HALT_ADDR
#endif

#endif
