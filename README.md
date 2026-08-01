# riscv-soc

RISC-V processor / SoC development, following the toolflow from
**RISC-V System-on-Chip Design** (Harris, Harris, Prikryl, Wallentowitz —
the book built around the CORE-V Wally core).

## Environment

Everything is provided by the Nix flake — no system installs:

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
| `verible`                       | SystemVerilog formatter / linter / language server                                                                       |
| `riscof`                        | RISC-V architecture compliance framework (DUT vs. Sail)                                                                  |
| `dtc`                           | Device tree compiler                                                                                                     |

Not covered by the flake: the book also uses commercial tools (Questa,
Synopsys DC) for some chapters — Verilator substitutes for simulation.

## Current State

The project is a learning implementation of a single-cycle RV32I SoC. The
current design has:

- a portable `single_stage` CPU core with IFU, controller, datapath, ALU,
  branch logic, register file, and a valid/ready data bus
- an LSU that handles RV32I byte/half/word load and store formatting, currently
  instantiated by the SoC wrapper between the core data bus and data memory
- synchronous instruction and data memories
- board-level memory-mapped peripherals for LEDs, timer, UART, buttons,
  switches, SPI, GPIO, and an I2C placeholder/state-machine path
- generated board constants shared between RTL and firmware headers
- a small RV32I SDK and example bare-metal apps
- Verilator lint and self-checking SystemVerilog testbenches for core modules,
  peripherals, board bus routing, and end-to-end RV32I behavior

The next architectural cleanup should probably happen before pipelining: move
the LSU semantics into the core so the SoC boundary is a simple byte-enable data
bus instead of carrying RISC-V load/store interpretation outside the CPU.

## Layout

```
rtl/cpu/lib/          reusable CPU RTL: decode, ALU, reg file, ISA package
rtl/cpu/single_stage/ single-stage core, SoC wrapper, memories, LSU, IFU
rtl/periph/           memory-mapped peripheral RTL
rtl/lib/              shared non-CPU RTL helpers
boards/<board>/       board constants, top-level RTL, pins, board headers
tb/single_stage/      CPU and single-stage SoC testbenches
tb/boards/<board>/    board/peripheral testbenches
sdk/riscv32/          RV32I bare-metal startup, linker script, headers
examples/apps/        RV32I example firmware
sw/smoke/             toolchain sanity check; not software for this core
docs/                 diagrams and vendor references
tools/                generated constants / tooling helpers
```

`DESIGN` is the CPU variant. It defaults to `single_stage`; future variants can
grow as new `rtl/cpu/<design>` + `tb/<design>` pairs.

## Project Docs

- `CONTRIBUTING.md` documents the working agreement, RTL ownership boundary,
  testbench conventions, and SystemVerilog style.
- `CHANGELOG.md` tracks project milestones and notable commit history.

## Near-Term Roadmap

1. Add or repair the focused load/store SoC test target so
   `make sim TB=core_load_store` runs from the existing
   `tb/single_stage/tb_core_load_store.S` program.
2. Move the LSU into the core boundary, leaving the SoC/data-memory interface
   with address, write data, read data, valid/ready, write/read, and byte
   enables.
3. Re-run core lint and RV32I/load-store simulations.
4. Start the pipelined variant once the memory boundary is clean.

## Quick check

```sh
nix develop
just smoke   # cross-compile sw/smoke, run it on spike and sail
just lint    # Verilator lint of rtl/cpu/single_stage
just sim     # build + run the default tb/single_stage testbench
just wave    # same, with a VCD, opened in GTKWave
```

The `just` recipes are thin wrappers over `make`; use `make` directly to pick
a design or turn on tracing:

```sh
make lint TOP=core
make sim TB=rv32i
make sim TB=core TRACE=1
```

## References

- Book's companion core: <https://github.com/openhwgroup/cvw> (CORE-V Wally)
- riscv-arch-test + riscof docs: <https://riscof.readthedocs.io>
