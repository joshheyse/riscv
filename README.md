# riscv-soc

RISC-V processor / SoC development, following the toolflow from
**RISC-V System-on-Chip Design** (Harris, Harris, Prikryl, Wallentowitz —
the book built around the CORE-V Wally core).

## Environment

Project build, simulation, synthesis, and firmware tools are provided by the
Nix flake — no system installs:

```sh
nix develop
```

| Tool                            | Book role                                                                                                                |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `riscv64-none-elf-gcc` / `-gdb` | Cross toolchain (book calls it `riscv64-unknown-elf-`; same tool, different prefix — pass `$CROSS_COMPILE` to Makefiles) |
| `spike`                         | riscv-isa-sim, the standard ISA simulator                                                                                |
| `sail-riscv`                    | Sail golden reference model (riscof reference)                                                                           |
| `qemu-system-riscv64`           | Fast full-system emulation (boot Linux, etc.)                                                                            |
| `verilator`                     | Cycle-accurate RTL simulation + lint                                                                                     |
| `gtkwave`                       | Waveform viewer                                                                                                          |
| `verible`                       | SystemVerilog formatter / style linter                                                                                   |
| `riscof`                        | RISC-V architecture compliance framework (DUT vs. Sail)                                                                  |
| `dtc`                           | Device tree compiler                                                                                                     |

Not covered by the flake: the book also uses commercial tools (Questa,
Synopsys DC) for some chapters — Verilator substitutes for simulation.

## Current State

The project is a learning implementation of an RV32I SoC. Its CPU is a
Chapter 7-style pipeline with IF/ID, ID/EX, EX/MEM, and MEM/WB stage registers.

The current design has:

- shared CPU building blocks for decode, ALU, branch logic, register file,
  instruction/data buses, instruction/data memory, LSU, and writeback muxing
- a `pipelined` CPU core with buffered fetch, execute-stage branch resolution,
  forwarding into execute, load-use stalls, store-data forwarding, and
  forwarding-aware hazard detection
- synchronous instruction and data memories
- board-level memory-mapped peripherals for LEDs, timer, UART, buttons,
  switches, SPI, GPIO, and an I2C placeholder/state-machine path
- generated board constants shared between RTL and firmware headers
- a small RV32I SDK and example bare-metal apps
- Verilator lint and self-checking SystemVerilog testbenches for core modules,
  peripherals, board bus routing, and end-to-end RV32I behavior

The pipelined core is correct enough to serve as the Chapter 7 baseline, but it
is intentionally simple: no caches, no MMU, no privileged traps, no branch
prediction, and simple IFU/LSU/bus timing.

## Layout

```
rtl/cpu/lib/          reusable CPU RTL: decode, ALU, reg file, ISA package
rtl/cpu/pipelined/    pipelined core, SoC wrapper, IFU, hazard/control helpers
rtl/periph/           memory-mapped peripheral RTL
rtl/lib/              shared non-CPU RTL helpers
boards/<board>/       board constants, top-level RTL, pins, board headers
tb/cpu/lib/           reusable CPU RTL testbenches
tb/cpu/pipelined/     pipelined CPU testbenches
tb/lib/               shared non-CPU RTL testbenches
tb/boards/<board>/    board/peripheral testbenches
sdk/riscv32/          RV32I bare-metal startup, linker script, headers
examples/apps/        RV32I example firmware
sw/smoke/             toolchain sanity check; not software for this core
docs/                 diagrams and vendor references
tools/                generated constants / tooling helpers
.slang/               slang-server workspace config and design-specific build filelists
```

`DESIGN` defaults to `pipelined` for build, lint, simulation, and board firmware
targets.

## Project Docs

- `CONTRIBUTING.md` documents the working agreement, RTL ownership boundary,
  testbench conventions, and SystemVerilog style.
- `CHANGELOG.md` tracks project milestones and notable commit history.

## Near-Term Roadmap

1. Treat the Chapter 7 pipelined baseline as functionally complete.
2. Start Chapter 8 privileged execution: machine-mode CSRs, `ecall`, `mret`,
   trap PC handling, and trap redirects.
3. Revisit the bus interface, caches, LSU, and IFU as the later book chapters
   introduce those pieces.
4. Keep improving focused pipeline tests and CPI microbenchmarks as the memory
   hierarchy evolves.

## Quick check

```sh
nix develop
just smoke   # cross-compile sw/smoke, run it on spike and sail
just lint    # Verilator lint of the pipelined design
just sim     # build + run the default pipelined core testbench
just wave    # same, with a VCD, opened in GTKWave
```

The `just` recipes are thin wrappers over `make`; use `make` directly to pick
a design or turn on tracing:

```sh
make lint TOP=core
make sim TB=rv32i
make sim TB=core TRACE=1
make lint TOP=soc
make board-app-test BOARD=sim BOARD_SIM=top_sim
```

## Editor Setup

SystemVerilog semantic navigation and diagnostics use `slang-server`, installed
through the Home Manager editor toolchain. The checked-in `.slang/server.json`
discovers the design-specific filelists in `.slang/builds/`.

Verible remains the formatter/style-lint tool. It is intentionally not used as
the semantic language server.

## References

- Book's companion core: <https://github.com/openhwgroup/cvw> (CORE-V Wally)
- riscv-arch-test + riscof docs: <https://riscof.readthedocs.io>
