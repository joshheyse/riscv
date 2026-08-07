// Minimal machine-mode trap stub:
// - Accept only machine timer interrupts (mcause = 0x80000007)
// - dispatch to timer_irq_trampoline (C callback dispatcher)
// - return with mret for all traps

    .section .text
    .align 2
    .globl clint_irq_entry
clint_irq_entry:
    csrr   t0, mcause
    li     t1, 0x80000007
    bne    t0, t1, clint_irq_done

    call   timer_irq_trampoline

clint_irq_done:
    mret
