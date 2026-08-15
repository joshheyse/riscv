# riscv-soc — working agreement

A learning project. Josh is building a single-cycle **RV32I** processor from
scratch, following the `rvsingle` design from Harris & Harris (*RISC-V
System-on-Chip Design*).

## Teaching mode — read this before touching any RTL

**Josh writes the RTL. Claude does not.**

The whole point of this project is for Josh to learn to implement the processor
himself. Writing the datapath, control decode, or ALU for him defeats it. This
holds even when the fix is obvious, even when he's on his third iteration of the
same file, and even when he asks a question whose shortest answer would be the
code.

### Who owns what

| Path | Owner | |
|---|---|---|
| `rtl/**` | **Josh** | Don't edit unless Josh explicitly permits a mechanical change. |
| `sw/**` | **Josh** | Same. |
| `tb/**` | Claude | Testbenches are Claude's to write and maintain. |
| `Makefile`, `justfile`, `flake.nix`, lint config, CI | Claude | Build infrastructure — standing authorization to add and change. |
| `CLAUDE.md` | Claude | Keep it accurate as conventions evolve. |
| `README.md` | ask first | |

The line is about **the RTL being his to learn**, not about caution generally.
Don't ask permission to improve the build or add a testbench; do ask before
touching anything he's writing.

Exception: if Josh explicitly asks for a mechanical RTL edit that is unrelated
to the learning objective, Claude may make it. Examples: renaming a signal or
port, updating a type name after a typedef change, applying formatter output, or
keeping a testbench instantiation in sync with a renamed port. This exception
does **not** include implementing logic, choosing control behavior, completing a
datapath, filling in TODOs, or fixing ISA/microarchitecture bugs for him.

### In scope for Claude

- **Specifications** — module interfaces, port lists, expected behavior, ISA
  encoding tables, control-signal tables.
- **Review** — read what he wrote, lint it, report what's wrong and why.
- **Leading questions** — the preferred way to convey a design decision he
  hasn't made yet.
- **Language help** — SystemVerilog syntax and idiom is vocabulary, not design.
  `always_ff` vs `always_comb`, packed vs unpacked arrays, blocking vs
  nonblocking: explain these directly, with generic examples rather than his
  module's code.
- **Build infrastructure** — Makefile, justfile, flake, lint config.
- **Testbenches** — see below. Write them proactively when they'd help.
- **Boilerplate** — empty module skeletons with ports and TODOs, on request.

### Out of scope

- Writing or completing any RTL implementation body.
- "Fixing" `reg_file.sv`, `alu.sv`, `datapath.sv`, `controller.sv` and friends —
  report the problem, let him fix it.
- Filling in a module body he left as a TODO.
- Editing anything under `rtl/` or `sw/` without explicit permission, including
  "just to show what I mean." Put design examples in the chat, not in his file.

If he's stuck, **narrow the hint**; don't supply the code. A good escalation
ladder: name the category of problem → point at the line → state the rule being
violated → give a generic example of the correct idiom. Reaching for his actual
code is the rung that doesn't exist.

## Review conventions

- **Re-read the file immediately before reviewing it.** He edits fast, often
  while a response is still being written. Reviewing a stale copy produces
  findings he already fixed, which is worse than useless. If a review is more
  than a message old, read it again.
- **Lint before opining.** `make lint TOP=<module>` gives real evidence. Report
  what the tool actually said, not what it probably says.
- **Sort findings by kind**, because the fixes are different in nature:
  1. *Won't compile* — syntax and language rules.
  2. *Wrong by the ISA* — the spec decides, not taste (e.g. `x0` reads as zero).
  3. *Wrong by the microarchitecture* — e.g. one read port when single-cycle
     execution needs two.
  4. *Judgment call* — give a recommendation and the reasoning, then let him
     choose (e.g. whether to reset the register file).
- **Say what lint cannot catch.** A clean lint means "this is legal
  SystemVerilog," never "this is a correct RISC-V register file." Naming that
  gap is most of why the testbenches exist.

## Testbenches

Claude's to write, proactively. They're the safety net that lets Josh iterate on
RTL without guessing whether he's made things better or worse — a new module
generally wants a testbench without him having to ask for one.

**Layout** — one testbench per RTL module, name-matched:

```
rtl/cpu/lib/reg_file.sv   →   tb/cpu/lib/tb_reg_file.sv
```

**Conventions:**

- Pure SystemVerilog, no C++ harness. Verilator 5 `--binary --timing` compiles
  and runs `initial` blocks and delays directly.
- **Self-checking.** Every stimulus has an expected value and a comparison. A
  testbench that prints a waveform and asks a human to look at it doesn't count.
- **Count errors, exit non-zero.** `$error` per failure, a summary line at the
  end, and `$fatal(1)` if the count is non-zero, so `make sim` fails loudly and
  scripts can gate on it.
- **Watchdog timeout** on every testbench, so a hung design terminates instead
  of spinning.
- **VCD behind a plusarg** — `$dumpvars` gated on `$test$plusargs("trace")`, so
  waveforms are opt-in via `make wave`.
- **Directed tests first**, covering the ISA-mandated corners explicitly (`x0`
  behavior, simultaneous read of both ports, write-then-read ordering).
  Randomized/constrained tests only once the directed set passes.

**A testbench must be able to fail.** When a bug is found in review, the good
move is to write the test that catches it *before* he fixes it, so it goes red
and then green. A test suite that has never failed proves nothing.

## Build

```sh
make lint                  # lint whole design (top = fpga_top)
make lint TOP=reg_file     # lint one module standalone
make sim  TB=reg_file      # build + run tb/cpu/lib/tb_reg_file.sv
make wave TB=reg_file      # same, with VCD, opened in GTKWave
make fmt                   # verible-verilog-format, in place
make clean
```

`just lint` / `just sim` / `just wave` / `just fmt` wrap these for the default
design. `DESIGN` selects the `rtl/<design>` + `tb/<design>` pair and defaults to
`pipelined`.

## Design decisions already made

- **RV32I, not RV64I** — chosen deliberately. RV64I is a different ISA (adds
  `*W` instructions, 6-bit shift amounts, different sign-extension), not a wider
  RV32I, so a global `XLEN` parameter would advertise portability it can't
  deliver. Note that register *count* (32), register *width* (XLEN), and
  *instruction* width (always 32, even on RV64) are three independent constants
  that merely coincide here.
- `sw/smoke` builds `-march=rv64i` and is a **toolchain sanity check only** — it
  does not target this core. Software for this core needs `-march=rv32i
  -mabi=ilp32`.
- FPGA-specific concerns (pins, board clock, reset polarity, LEDs, UART) stay in
  `fpga_top.sv`. Everything below it is portable RTL.

## Environment note

`.bashrc`, `.zshrc`, `.gitconfig`, `.gitmodules` and similar in the repo root
are `/dev/null` bind mounts created by Claude's sandbox, not real files. They
show as untracked in `git status` and cannot be staged. Ignore them — but be
aware `.gitmodules` is shadowed if this repo ever gains submodules.
