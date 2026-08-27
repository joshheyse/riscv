# Changelog

Project milestones and notable commit history.

## Milestones

### 1. Development Environment

- Added a Nix shell with the RISC-V cross toolchain, Spike, Sail, QEMU,
  Verilator, GTKWave, Verible, and RISCOF.
- Added editor support for assembly and generated compile/file lists.
- Established the `make`/`just` workflow for lint, simulation, formatting,
  firmware builds, board simulation, and board bitstream generation.

Key commits: `ce304e2`, `649e3ee`, `3017eef`, `1135cac`.

### 2. First RV32I Single-Stage Core

- Added the initial RV32I CPU modules and module-level testbenches.
- Integrated controller, datapath, instruction fetch, instruction memory, and
  SoC wrapper.
- Documented the single-stage structure.

Key commits: `eb6d315`, `12c8267`, `d7efcc8`, `f9b25ac`, `89f1fa8`,
`578c6e4`.

### 3. ISA Coverage and Firmware Path

- Added RV32I memory and halt coverage in assembly-driven tests.
- Added a small firmware SDK, board simulator path, and example apps.
- Made the core build firmware for `rv32i`/`ilp32`; `sw/smoke` remains a
  separate RV64 toolchain sanity check.

Key commits: `c1f340f`, `5d91cf0`, `0067b56`.

### 4. Board and MMIO Bring-Up

- Added the ECP5 board flow.
- Added generated board memory maps/constants shared by RTL and C headers.
- Added board bus routing and MMIO peripherals: timer, UART timing constants,
  switches/buttons, SPI, GPIO, and I2C support work.
- Added focused board/peripheral testbenches.

Key commits: `ab6f83a`, `5a2558e`, `9446631`, `06d58e1`, `b05bd34`,
`30253c7`, `dc22edb`, `f899ca8`, `f19355f`, `5730417`, `850811e`,
`d842e28`, `42223f0`, `65711ec`, `f7aefdb`, `c9840b4`, `63a6662`,
`54ca65c`, `a1e016b`, `133ce60`.

### 5. Memory Timing and Bus Cleanup

- Split simulator and physical board constants.
- Added shared muxing helpers for board/sim bus reads.
- Moved instruction and data memory toward synchronous behavior.
- Split data memory from the LSU.
- Added a data-memory ready handshake.
- Renamed data-bus signals for clarity.
- Documented and enforced the SystemVerilog naming conventions used before
  pipeline work, including private `_` names, instance names, compact
  connections, `_en` enable names, and explicit memory data-bus names.

Key commits: `1ab1e5f`, `8f01413`, `00a2236`, `16f08d1`, `b5f2151`,
`f7c1fa7`, `6c2f870`, `e74ddb3`, `7719849`.

### 6. Chapter 7 Pipelined Core Baseline

- Moved the LSU into the core boundary and normalized the data bus around
  request/response payloads with byte write masks.
- Added the `pipelined` CPU variant beside `single_stage`, using IF/ID, ID/EX,
  EX/MEM, and MEM/WB stage-register bundles.
- Added buffered instruction fetch, pipeline control, redirect control, and a
  forwarding-aware hazard unit.
- Moved branch/jump resolution into execute so branch compares use forwarded
  operands.
- Added execute and MEM/WB forwarding, load-use stalls, store-data forwarding,
  and a decode-side MEM/WB bypass.
- Switched the simulated board top to select `single_stage` or `pipelined` with
  `DESIGN`, and added end-to-end firmware regressions for both.
- Added `board-cpi` tooling to compare simulated-board CPI across the two CPU
  variants.

Current `just board-cpi top_sim sim` snapshot:

| App                 | Single-stage CPI | Pipelined CPI |
| ------------------- | ---------------: | ------------: |
| `uart_halt_c`       |             3.01 |          3.26 |
| `uart_pattern_halt` |             3.00 |          3.30 |
| `memory_copy_halt`  |             3.03 |          3.17 |
| `led_count_halt`    |             3.00 |          2.77 |

Known limitations at this milestone: no privileged execution, caches, MMU, or
branch prediction; simple IFU/LSU timing; and a memory hierarchy that will
change in later book chapters.

Key commits: `19943b6`, `afdac51`, `4967a92`, `c914e27`, `b365925`,
`041f413`, `2bc52c2`.

### 7. Bare Supervisor Mode

- Added machine, supervisor, and user privilege-state transitions with
  privilege-aware CSR and SYSTEM-instruction access checks.
- Added supervisor trap CSRs and views: `sstatus`, `sie`, `sip`, `stvec`,
  `sscratch`, `sepc`, `scause`, and `stval`.
- Added synchronous-exception delegation through WARL `medeleg`, supervisor
  software/timer/external interrupt delegation through WARL `mideleg`, and
  direct/vectored trap routing through the selected privilege's `xtvec`.
- Added supervisor trap entry, `SIE`/`SPIE`/`SPP` stacking, `sret`, and
  `mstatus.TSR` enforcement.
- Added a legal Bare-only `satp`; Sv32 translation, page-table walking, TLBs,
  page faults, `SFENCE.VMA`, and PMP remain separate future work.
- Added module and pipelined integration coverage for delegated exceptions,
  delegated interrupts, supervisor trap-state preservation, `sret`, TSR, and
  `sscratch`.
- Kept `senvcfg` intentionally unsupported because the optional cache-block,
  pointer-masking, and FIOM behavior it controls is not implemented.

Key commits: `a8b9e2f`, `a6be1a3`, `70243df`.

### 8. Set-Associative L1 Caches

- Added separate instruction and data L1 caches and inferred block RAM for
  cache storage.
- Added cache maintenance and `FENCE.I` ordering.
- Refactored cache storage into reusable ways, then expanded the caches from
  direct-mapped to two-way and four-way set associativity.
- Added two-way LRU and four-way pseudo-LRU replacement policies.

Key commits: `a8b034c`, `77c7e48`, `5546980`, `b70da17`, `1c85dd8`,
`5920533`, `7db4c06`.

### 9. RV32M Integer Multiply and Divide

- Added RV32M decode and execution support for multiply, divide, and remainder
  instructions.
- Initially implemented division as a combinational datapath. FPGA timing
  measurements identified this as the major clock-frequency regression and
  motivate a future iterative multi-cycle divider.

Key commit: `47436c0`.

### 10. Initial Sv32 Translation

- Added legalized `satp` state, page-fault causes, `SFENCE.VMA`, and the
  supervisor permission fields needed for translation.
- Added an Sv32 page-table walker and permission checks.
- Inserted virtual-memory adapters ahead of the instruction and data caches.
- Added a combinational Bare/M-mode request bypass while keeping translated
  accesses on the page-table-walker path.

Key commits: `2043be5`, `60ac66d`, `4578f56`, `7b74dc2`, `af1e042`,
`55219fc`.

### 11. Multicycle RV32M Execution

- Replaced the combinational divider with a 32-step restoring divider and the
  combinational multiplier with a 32-step shift-add multiplier.
- Added request/response backpressure, pipeline holds, and cancellation when a
  multicycle instruction is flushed.
- Removed all inferred DSP multipliers from the FPGA design and recovered
  routed timing from 8.03 MHz to 45.92 MHz on the Sv32-integrated core.

Key commit: `f026e60`.

## Performance History

Keep this table current when a major architectural feature changes CPI, FPGA
timing, or resource use. Measure routed timing on the
`lfe5um5g_85f_evn` speed-grade-8 target with the same nextpnr settings. Measure
CPI with a fixed-work benchmark that does not poll UART, timers, or another
real-time peripheral. The current benchmark is `perf_fixed_halt`, which retires
1,699 instructions in every measured architecture. A valid pipelined
retirement event is a non-faulting MEM/WB entry leaving the stage; a held entry
must not be counted repeatedly. The terminal simulation-halt store is counted
when its memory transaction completes because simulation stops before it can
reach MEM/WB.

Resource counts come from the synthesized ECP5 netlist. LUTs include ordinary
`LUT4` cells plus the LUT equivalents consumed by carry and distributed-RAM
cells; FFs, BRAMs, and multipliers count `TRELLIS_FF`, `DP16KD`, and
`MULT18X18D` cells respectively.

The earlier UART-based CPI snapshot remains useful as a historical record, but
is not directly comparable: UART polling changes the dynamic instruction count
when memory-system latency changes.

| Architecture | Milestone                                     | Commit    | Cycles | Instret |  CPI | Routed Fmax | Est. MIPS |    LUTs |     FFs |   BRAMs | Multipliers |
| ------------ | --------------------------------------------- | --------- | -----: | ------: | ---: | ----------: | --------: | ------: | ------: | ------: | ----------: |
| Single-stage | Final working core                            | `1644a56` |  5,373 |   1,699 | 3.16 |   59.86 MHz |     18.93 |   4,765 |     597 |       2 |           0 |
| Pipelined    | Bare supervisor privilege and delegated traps | `70243df` |  3,963 |   1,699 | 2.33 |   ~68.8 MHz |    ~29.50 |   5,989 |   1,766 |       2 |           0 |
| Pipelined    | Unified memory baseline                       | `eeb8923` |  6,362 |   1,699 | 3.74 |   66.89 MHz |     17.86 |   7,339 |   1,658 |       2 |           0 |
| Pipelined    | Cache associativity benchmark support         | `4059c4c` |  5,989 |   1,699 | 3.53 |   65.46 MHz |     18.57 |  10,503 |   2,581 |      10 |           0 |
| Pipelined    | Four-way cache replacement                    | `5920533` |  5,989 |   1,699 | 3.53 |   61.39 MHz |     17.42 |   8,648 |   2,025 |       7 |           0 |
| Pipelined    | RV32M execution                               | `47436c0` |  5,989 |   1,699 | 3.53 |    ~7.9 MHz |     ~2.24 |  19,205 |   2,026 |       7 |          10 |
| Pipelined    | Sv32 integration and request bypass           | `55219fc` |  7,832 |   1,699 | 4.61 |    8.03 MHz |      1.74 |  17,544 |   2,759 |       7 |          10 |
| Pipelined    | Multicycle RV32M multiply and divide          | `f026e60` |  7,832 |   1,699 | 4.61 |   45.92 MHz |      9.96 |  11,087 |   3,101 |       7 |           0 |
| Pipelined    | Registered physical-memory boundary           | `750d373` |  7,993 |   1,699 | 4.70 |   56.39 MHz |     11.99 |  10,673 |   3,208 |       7 |           0 |
| Pipelined    | Decoupled multiplier result slot              | this commit |  7,993 |   1,699 | 4.70 |   60.81 MHz |     12.93 |  11,354 |   3,207 |       7 |           0 |

For architectural comparisons, also report estimated instruction throughput:

```text
instructions/second = routed Fmax / CPI
```
