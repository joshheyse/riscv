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

Known limitations: no privileged execution, no caches, no MMU, no branch
prediction, simple IFU/LSU timing, and a memory hierarchy that will change in
later book chapters.

Key commits: `19943b6`, `afdac51`, `4967a92`, `c914e27`, `b365925`,
`041f413`, `2bc52c2`.
