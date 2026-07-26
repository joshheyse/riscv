# riscv-soc

RISC-V processor / SoC development, following the toolflow from
**RISC-V System-on-Chip Design** (Harris, Harris, Prikryl, Wallentowitz —
the book built around the CORE-V Wally core).

## Environment

Everything is provided by the Nix flake — no system installs:

```sh
nix develop
```

| Tool | Book role |
|---|---|
| `riscv64-none-elf-gcc` / `-gdb` | Cross toolchain (book calls it `riscv64-unknown-elf-`; same tool, different prefix — pass `$CROSS_COMPILE` to Makefiles) |
| `spike` | riscv-isa-sim, the standard ISA simulator |
| `sail-riscv` | Sail golden reference model (riscof reference) |
| `qemu-system-riscv64` | Fast full-system emulation (boot Linux, etc.) |
| `verilator` | Cycle-accurate RTL simulation + lint |
| `gtkwave` | Waveform viewer |
| `verible` | SystemVerilog formatter / linter / language server |
| `riscof` | RISC-V architecture compliance framework (DUT vs. Sail) |
| `dtc` | Device tree compiler |

Not covered by the flake: the book also uses commercial tools (Questa,
Synopsys DC) for some chapters — Verilator substitutes for simulation.

## Layout

```
rtl/<design>/   processor / SoC RTL (SystemVerilog)
tb/<design>/    testbenches
sw/             bare-metal test programs (sw/smoke = toolchain sanity check)
tests/          riscof compliance configuration
docs/           notes
```

`<design>` is a core variant — `single_stage` today, later `multicycle`,
`pipelined`, … The `Makefile` is parameterised by `DESIGN` (default
`single_stage`), so a new variant is just a new `rtl/<design>` + `tb/<design>`
pair with no build changes.

## Quick check

```sh
nix develop
just smoke   # cross-compile sw/smoke, run it on spike and sail
just lint    # Verilator lint of rtl/single_stage
just sim     # build + run tb/single_stage
just wave    # same, with a VCD, opened in GTKWave
```

The `just` recipes are thin wrappers over `make`; use `make` directly to pick
a design or turn on tracing:

```sh
make sim DESIGN=single_stage
make run TRACE=1
```

## References

- Book's companion core: <https://github.com/openhwgroup/cvw> (CORE-V Wally)
- riscv-arch-test + riscof docs: <https://riscof.readthedocs.io>
