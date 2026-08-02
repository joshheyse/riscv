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

The project is a learning implementation of an RV32I SoC. There are now two CPU
variants selected with `DESIGN`:

- `single_stage`: the original portable core, matching the book's early
  single-cycle structure.
- `pipelined`: a Chapter 7-style baseline pipeline with IF/ID, ID/EX, EX/MEM,
  and MEM/WB stage registers.

The current design has:

- shared CPU building blocks for decode, ALU, branch logic, register file,
  instruction/data buses, instruction/data memory, LSU, and writeback muxing
- a `single_stage` CPU core with IFU, controller, datapath, ALU, branch logic,
  register file, LSU, and a valid/ready data bus
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
rtl/cpu/single_stage/ single-stage core and SoC wrapper
rtl/cpu/pipelined/    pipelined core, SoC wrapper, IFU, hazard/control helpers
rtl/periph/           memory-mapped peripheral RTL
rtl/lib/              shared non-CPU RTL helpers
boards/<board>/       board constants, top-level RTL, pins, board headers
tb/single_stage/      CPU and single-stage SoC testbenches
tb/pipelined/         pipelined CPU testbenches
tb/boards/<board>/    board/peripheral testbenches
sdk/riscv32/          RV32I bare-metal startup, linker script, headers
examples/apps/        RV32I example firmware
sw/smoke/             toolchain sanity check; not software for this core
docs/                 diagrams and vendor references
tools/                generated constants / tooling helpers
```

`DESIGN` is the CPU variant. It defaults to `single_stage`; use
`DESIGN=pipelined` to build, lint, simulate, or run board firmware against the
pipelined core.

## CPI Snapshot

`just board-cpi top_sim sim` compares the simulated-board firmware suite against
both CPU variants. Current CPI after the initial forwarding work:

| App                 | Single-stage CPI | Pipelined CPI |
| ------------------- | ---------------: | ------------: |
| `uart_halt_c`       |             3.01 |          3.26 |
| `uart_pattern_halt` |             3.00 |          3.30 |
| `memory_copy_halt`  |             3.03 |          3.17 |
| `led_count_halt`    |             3.00 |          2.77 |

Pipeline throughput should be evaluated as `Fmax / CPI`; the pipelined core can
still be faster overall even before CPI beats the single-stage design.

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
just lint    # Verilator lint of the default single_stage design
just sim     # build + run the default single_stage testbench
just wave    # same, with a VCD, opened in GTKWave
```

The `just` recipes are thin wrappers over `make`; use `make` directly to pick
a design or turn on tracing:

```sh
make lint TOP=core
make sim TB=rv32i
make sim TB=core TRACE=1
make lint DESIGN=pipelined TOP=soc
make board-app-test DESIGN=pipelined BOARD=sim BOARD_SIM=top_sim
just board-cpi top_sim sim
```

## References

- Book's companion core: <https://github.com/openhwgroup/cvw> (CORE-V Wally)
- riscv-arch-test + riscof docs: <https://riscof.readthedocs.io>
