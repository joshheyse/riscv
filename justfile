cross := env_var_or_default("CROSS_COMPILE", "riscv64-none-elf-")

# Which rtl/<design> + tb/<design> pair the recipes act on.
design := "single_stage"
arch := "rv32i"
board := "lfe5um5g_85f_evn"
app := ""
sim_board := "sim"
sim_top := "top_sim"
default_app := "boards/" + board + "/rtl/programs/led_skip.S"
default_sim_app := "examples/apps/uart_halt_c"

_default:
    @just --list

# Cross-compile the smoke test and run it on both ISA simulators.
smoke:
    mkdir -p build
    {{ cross }}gcc -march=rv64i -mabi=lp64 -nostdlib -nostartfiles \
        -T sw/smoke/link.ld sw/smoke/smoke.S -o build/smoke.elf
    spike build/smoke.elf && echo "spike: PASS"
    sail_riscv_sim build/smoke.elf > build/sail.log && echo "sail:  PASS"

# Lint the RTL. Pass a module name to lint it standalone: just lint reg_file
lint top="core":
    make lint DESIGN={{ design }} TOP={{ top }}

# Check project-specific SystemVerilog style rules.
style:
    make style DESIGN={{ design }}

# Build and run a testbench: just sim reg_file
sim tb="core":
    make sim DESIGN={{ design }} TB={{ tb }}

# Run a testbench with tracing and open the VCD: just wave reg_file
wave tb="core":
    make wave DESIGN={{ design }} TB={{ tb }}

# Run the simulated platform: just design=pipelined app=examples/apps/csr_halt arch=rv32i_zicsr board-sim
board-sim:
    @app="{{ app }}"; \
    [ -n "$app" ] || app="{{ default_sim_app }}"; \
    make board-sim DESIGN="{{ design }}" BOARD="{{ sim_board }}" BOARD_SIM="{{ sim_top }}" APP="$app" RISCV_ARCH="{{ arch }}"

# Run simulated-board firmware regressions: just design=pipelined board-app-test
board-app-test sim="top_sim" target="sim":
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-app-test DESIGN={{ design }} BOARD="$board" BOARD_SIM="{{ sim }}" RISCV_ARCH="{{ arch }}"

# Compare simulated-board CPI between single_stage and pipelined.
board-cpi sim="top_sim" target="sim":
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-cpi BOARD="$board" BOARD_SIM="{{ sim }}"

# Run a board peripheral testbench: just board-tb timer_mmio
board-tb tb="timer_mmio" target=board:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-tb BOARD="$board" BOARD_TB="{{ tb }}"

# Build the selected board bitstream: just board-build boards/lfe5um5g_85f_evn path/to/app.c
board-build target=board app=default_app:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-build DESIGN={{ design }} BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Synthesize the selected board top to JSON: just board-synth boards/lfe5um5g_85f_evn path/to/app.c
board-synth target=board app=default_app:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-synth DESIGN={{ design }} BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Place and route the selected board design: just board-pnr boards/lfe5um5g_85f_evn path/to/app.c
board-pnr target=board app=default_app:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-pnr DESIGN={{ design }} BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Program the selected board bitstream into FPGA SRAM: just board-flash boards/lfe5um5g_85f_evn path/to/app.c
board-flash target=board app=default_app:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-flash DESIGN={{ design }} BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Program a board bitstream into FPGA SRAM: just flash boards/lfe5um5g_85f_evn
flash target=board app=default_app:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-flash DESIGN={{ design }} BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Run every testbench in the design and report a pass/fail summary.
test:
    make style DESIGN={{ design }}
    @fail=0; \
    for f in tb/{{ design }}/tb_*.sv; do \
        [ -e "$f" ] || continue; \
        name=$(basename "$f" .sv); name=$(echo "$name" | sed 's/^tb_//'); \
        printf '%-20s ' "$name"; \
        if out=$(make sim DESIGN={{ design }} TB="$name" 2>&1); then \
            res=$(echo "$out" | grep -oE '(PASS|FAIL) \(.*\)' | tail -1); \
            if [ -n "$res" ]; then echo "$res"; \
            else echo "ran (no self-checks)"; fi; \
        else \
            fail=1; printf 'FAIL\n'; \
            echo "$out" | grep -E '%Error|: FAIL' | head -5 | sed 's/^/    /'; \
        fi; \
    done; \
    exit $fail

# Regenerate verible.filelist for the language server.
filelist:
    make filelist

# Regenerate compile_commands.json for clangd.
clangd target=board:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make compile-commands BOARD="$board"

# Build an app into ELF/bin/readmemh outputs: just app-build path/to/app.c
app-build app=default_app target=board:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make app-build BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Regenerate generated board constants files: just board-constants boards/lfe5um5g_85f_evn
board-constants target=board:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make board-constants BOARD="$board"

# Disassemble an app: just app-dump path/to/app.c
app-dump app=default_app target=board:
    @board="{{ target }}"; \
    board="${board#boards/}"; \
    make app-dump BOARD="$board" APP="{{ app }}" RISCV_ARCH="{{ arch }}"

# Format the design's RTL and testbenches with verible.
fmt:
    make fmt DESIGN={{ design }}

# Check formatting without modifying files.
fmt-check:
    make fmt-check DESIGN={{ design }}

clean:
    make clean DESIGN={{ design }}
    rm -rf obj_dir riscof_work
