# Linux Bring-Up Checklist

The target is a conventional single-hart RV32 system that enters M-mode
firmware after reset and runs Linux in S-mode. The initial Linux configuration
should be deliberately small: uniprocessor, no modules, a built-in initramfs,
and only the drivers needed by this SoC.

## 1. Architectural timer support

- [x] Expose the CLINT `mtime` value through the `time` and `timeh` CSRs.
- [x] Implement `mcounteren`, including `TM` access control for S-mode.
- [x] Implement `scounteren` for eventual userspace counter access.
- [x] Verify `mtimecmp` timer interrupt generation and delegation.
- [x] Provide the SBI timer service.
- [ ] Describe the timer frequency with `timebase-frequency` in the device tree.

The timer is a functional Linux requirement. `cycle`/`cycleh` and
`instret`/`instreth` should also be exposed for profiling, although they are not
required for the earliest boot milestone.

## 2. Complete the A extension

- [x] Decode and execute `LR.W` and `SC.W`.
- [x] Decode and execute `AMOSWAP.W` and `AMOADD.W`.
- [x] Decode and execute `AMOXOR.W`, `AMOAND.W`, and `AMOOR.W`.
- [x] Decode and execute signed `AMOMIN.W` and `AMOMAX.W`.
- [x] Decode and execute unsigned `AMOMINU.W` and `AMOMAXU.W`.
- [x] Track the load-reservation address.
- [x] Invalidate reservations on conflicting stores and relevant traps/events.
- [x] Implement correct `.aq` and `.rl` ordering semantics.
- [x] Add directed and architectural tests for reservation and AMO behavior.

Linux relies on atomic operations. A conservative implementation is acceptable
for the initial single-hart core.

## 3. Harden Sv32 correctness

- [x] Walk both Sv32 page-table levels.
- [x] Support level-one superpage leaves.
- [x] Check U/S permissions, `SUM`, and `MXR`.
- [x] Check accessed and dirty bits.
- [x] Distinguish page faults from physical access faults.
- [x] Apply `MPRV` and `MPP` to the effective privilege of data accesses.
- [x] Keep `satp` and the translation context stable throughout an active walk.
- [x] Verify that `stval` receives the faulting virtual address.
- [x] Verify page-table accesses are physical and cannot recursively translate.
- [x] Define behavior when software changes a PTE during an active walk.
- [x] Verify the required ordering semantics of `SFENCE.VMA`.

The walker samples each PTE on its individual memory-response transfer. It does
not provide an atomic snapshot across page-table levels or retry a walk if a PTE
changes concurrently. Page-table software must synchronize updates and execute
`SFENCE.VMA` as required. Walker memory requests use the physical `mem_if` path
below the translation adapters, so page-table accesses cannot recursively start
another translation.

`SFENCE.VMA` serializes the pipeline, cleans the data cache, invalidates the
instruction cache, and then applies selective TLB invalidation before refetch.
The `sv32_sfence_order_halt` regression rewrites a cached leaf PTE and verifies
that a subsequent instruction fetch observes the newly mapped physical page.

## 4. Add translation lookaside buffers

- [x] Add separate ITLB and DTLB instances.
- [x] Start with a small fully associative organization.
- [x] Store VPN, PPN, page level, permissions, ASID, and global status.
- [x] Check permissions on every TLB hit.
- [x] Share the existing page-table walker between TLB misses.
- [x] Preserve the current combinational Bare/M-mode bypass.
- [x] Implement ASID storage and matching.
- [x] Implement selective `SFENCE.VMA` invalidation using `rs1` and `rs2`.
- [x] Add a simple replacement policy such as round-robin.
- [x] Test ordinary pages, superpages, global mappings, ASIDs, permissions, and
      invalidation.

The walker is sufficient for functional translation without a TLB. The TLB is
needed to make translated execution practical, but is not by itself a Linux
correctness requirement.

## 5. Audit the privileged architecture

- [x] Report implemented ISA features accurately through `misa`.
- [x] Verify CSR privilege and read-only access checks.
- [x] Verify `medeleg`, `mideleg`, `mie`, `mip`, `sie`, and `sip` behavior.
- [x] Verify synchronous trap and interrupt priority.
- [x] Verify `MRET`, `SRET`, and `WFI` behavior.
- [x] Verify `FENCE.I` and `SFENCE.VMA` behavior end to end.
- [x] Implement PMP for normal firmware isolation and OpenSBI compatibility.
- [x] Run the relevant RISC-V architectural tests.

The audit includes directed module and pipelined-core regressions, the
`pmp_halt`, `fence_i_order_halt`, and `sv32_sfence_order_halt` end-to-end apps,
and a RISCOF comparison against Sail. The pinned RISC-V Architectural Test
Suite 3.8.18 privilege/Zifencei subset passes all 16 selected tests.

## 6. Define a stable platform

- [ ] Freeze the physical address map for boot ROM, RAM, CLINT, PLIC, UART, and
      optional SPI flash.
- [ ] Provide enough main memory for Linux in simulation.
- [ ] Connect and validate external SDRAM or DDR for FPGA Linux operation.
- [ ] Define the reset vector and firmware-loading mechanism.
- [ ] Keep the simulated and FPGA-visible platform contracts aligned.

FPGA block RAM is not large enough for a useful Linux system. Simulation RAM is
the easiest first target before integrating external memory hardware.

## 7. Complete Linux-visible interrupts

- [ ] Deliver timer interrupts to S-mode through SBI and delegation.
- [ ] Provide a supervisor external-interrupt path through the PLIC or firmware.
- [ ] Verify PLIC enable, priority, threshold, claim, and complete behavior.
- [ ] Add UART interrupt support.
- [ ] Verify the interrupt topology matches the device tree.

## 8. Provide M-mode firmware

- [ ] Decide between a minimal project-specific SBI implementation and OpenSBI.
- [ ] Implement the SBI base extension required by the selected kernel.
- [ ] Implement SBI timer programming.
- [ ] Provide an early console path.
- [ ] Implement system reset or shutdown.
- [ ] Initialize the platform and enter Linux in S-mode.
- [ ] Enter Linux with `a0` containing the hart ID.
- [ ] Enter Linux with `a1` containing the device-tree address.
- [ ] Enter Linux with `satp` in Bare mode.

The intended boot flow is:

```text
reset -> M-mode firmware/OpenSBI -> S-mode Linux -> userspace
```

## 9. Create the device tree

- [ ] Describe the CPU and its implemented ISA extensions.
- [ ] Declare `riscv,sv32` as the MMU type.
- [ ] Describe the hart and interrupt-controller relationships.
- [ ] Describe RAM at its actual physical range.
- [ ] Describe the CLINT, PLIC, and UART using compatible bindings.
- [ ] Set `timebase-frequency`.
- [ ] Select the boot console.
- [ ] Describe the built-in initramfs when applicable.

## 10. Build and boot a minimal Linux image

- [ ] Build an RV32 uniprocessor kernel.
- [ ] Disable modules, networking, and unrelated device drivers initially.
- [ ] Build in the serial console and platform drivers.
- [ ] Build a minimal BusyBox initramfs with a simple `/init`.
- [ ] Package the kernel, firmware, device tree, and initramfs reproducibly.

Track bring-up with these milestones:

- [ ] Execute the first kernel instruction.
- [ ] Complete early page-table setup and enable Sv32.
- [ ] Handle the first S-mode trap correctly.
- [ ] Print through the early console.
- [ ] Receive regular timer ticks.
- [ ] Mount the initramfs.
- [ ] Execute `/init`.
- [ ] Reach an interactive shell.

## Verification strategy

- [ ] Add directed tests for every new CSR, instruction, and TLB operation.
- [ ] Add page-table permission, fault, superpage, and invalidation stress tests.
- [ ] Differentially test architectural behavior against Spike or QEMU.
- [ ] Run a translated supervisor-mode program before attempting Linux.
- [ ] Preserve CPI, maximum-frequency, and resource measurements in the
      performance history as the system grows.
