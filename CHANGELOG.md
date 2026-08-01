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

Key commits: `1ab1e5f`, `8f01413`, `00a2236`, `16f08d1`, `b5f2151`,
`f7c1fa7`, `6c2f870`, `e74ddb3`, `7719849`.

