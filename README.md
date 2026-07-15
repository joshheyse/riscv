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
rtl/    processor / SoC RTL (SystemVerilog)
tb/     testbenches
sw/     bare-metal test programs (sw/smoke = toolchain sanity check)
tests/  riscof compliance configuration
docs/   notes
```

## Quick check

```sh
nix develop
just smoke   # cross-compile sw/smoke, run it on spike and sail
```

## References

- Book's companion core: <https://github.com/openhwgroup/cvw> (CORE-V Wally)
- riscv-arch-test + riscof docs: <https://riscof.readthedocs.io>
