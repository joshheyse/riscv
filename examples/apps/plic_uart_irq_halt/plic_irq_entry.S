// Test-only leaf handler. UART framing gives main enough time to reach its
// g_done wait loop before this runs; that loop uses a5, so t0-t3 are available
// here without stack traffic. This isolates PLIC behavior from stack accesses
// during trap handling.

    .section .text
    .align 2
    .globl plic_irq_entry
plic_irq_entry:
    li   t0, 0x0c200004
    lw   t1, 0(t0)
    la   t2, g_claimed
    sw   t1, 0(t2)

    li   t2, 0x10001004
    lw   t3, 0(t2)
    la   t2, g_received
    sw   t3, 0(t2)

    // Complete only after consuming RX, which lowers the UART level request.
    sw   t1, 0(t0)
    la   t0, g_done
    li   t1, 1
    sw   t1, 0(t0)
    mret
