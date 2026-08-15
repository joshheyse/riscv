@AGENTS.md

## Supervisor-mode scope

The first supervisor-mode implementation uses physical addressing only:

- M-, S-, and U-mode instruction fetches and data accesses use the existing
  physical address path unchanged.
- `satp` is present so supervisor software can probe it, but its `MODE` field is
  WARL and fixed to Bare (`0`). Writes cannot enable Sv32, and reads return
  zero.
- No page-table walk, TLB, address translation, `SFENCE.VMA`, or page-fault
  exceptions are included in this milestone.
- Physical memory protection is also deferred. Until PMP is implemented,
  privilege mode affects CSR/system-instruction access and trap routing, but
  does not restrict physical memory or MMIO access.

This scope still includes supervisor CSRs, M-to-S trap delegation, supervisor
trap entry, supervisor interrupt handling, and `sret`; those are independent of
Sv32 translation.

Implemented supervisor state includes `sstatus`, `sie`, `sip`, `stvec`,
`sscratch`, `sepc`, `scause`, and `stval`. `medeleg` and `mideleg` are WARL and
retain only trap causes implemented by this core. `mstatus.TSR` controls S-mode
use of `sret`. `senvcfg` remains intentionally unsupported until the extensions
it controls are implemented.
