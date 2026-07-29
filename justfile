cross := env_var_or_default("CROSS_COMPILE", "riscv64-none-elf-")

# Which rtl/<design> + tb/<design> pair the recipes act on.
design := env_var_or_default("DESIGN", "single_stage")
board := env_var_or_default("BOARD", "lfe5um5g_85f_evn")
default_app := "boards/" + board + "/rtl/programs/led_skip.S"

_default:
    @just --list

# Cross-compile the smoke test and run it on both ISA simulators.
smoke:
    mkdir -p build
    {{cross}}gcc -march=rv64i -mabi=lp64 -nostdlib -nostartfiles \
        -T sw/smoke/link.ld sw/smoke/smoke.S -o build/smoke.elf
    spike build/smoke.elf && echo "spike: PASS"
    sail_riscv_sim build/smoke.elf > build/sail.log && echo "sail:  PASS"

# Lint the RTL. Pass a module name to lint it standalone: just lint reg_file
lint top="core":
    make lint DESIGN={{design}} TOP={{top}}

# Build and run a testbench: just sim reg_file
sim tb="core":
    make sim DESIGN={{design}} TB={{tb}}

# Run a testbench with tracing and open the VCD: just wave reg_file
wave tb="core":
    make wave DESIGN={{design}} TB={{tb}}

# Run a board-level simulator: just board-sim top_sim examples/apps/uart_halt_c
board-sim sim="top_sim" app=default_app target=board:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-sim BOARD="$board" BOARD_SIM="{{sim}}" APP="{{app}}"

# Run a board peripheral testbench: just board-tb timer_mmio
board-tb tb="timer_mmio" target=board:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-tb BOARD="$board" BOARD_TB="{{tb}}"

# Build the selected board bitstream: just board-build boards/lfe5um5g_85f_evn path/to/app.c
board-build target=board app=default_app:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-build BOARD="$board" APP="{{app}}"

# Synthesize the selected board top to JSON: just board-synth boards/lfe5um5g_85f_evn path/to/app.c
board-synth target=board app=default_app:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-synth BOARD="$board" APP="{{app}}"

# Place and route the selected board design: just board-pnr boards/lfe5um5g_85f_evn path/to/app.c
board-pnr target=board app=default_app:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-pnr BOARD="$board" APP="{{app}}"

# Program the selected board bitstream into FPGA SRAM: just board-flash boards/lfe5um5g_85f_evn path/to/app.c
board-flash target=board app=default_app:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-flash BOARD="$board" APP="{{app}}"

# Program a board bitstream into FPGA SRAM: just flash boards/lfe5um5g_85f_evn
flash target=board app=default_app:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make board-flash BOARD="$board" APP="{{app}}"

# Run every testbench in the design and report a pass/fail summary.
test:
    @fail=0; \
    for f in tb/{{design}}/tb_*.sv; do \
        [ -e "$f" ] || continue; \
        name=$(basename "$f" .sv); name=$(echo "$name" | sed 's/^tb_//'); \
        printf '%-20s ' "$name"; \
        if out=$(make sim DESIGN={{design}} TB="$name" 2>&1); then \
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
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make compile-commands BOARD="$board"

# Build an app into ELF/bin/readmemh outputs: just app-build path/to/app.c
app-build app=default_app target=board:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make app-build BOARD="$board" APP="{{app}}"

# Regenerate generated memory-map files for a board: just memmap boards/lfe5um5g_85f_evn
memmap target=board:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make memmap BOARD="$board"

# Disassemble an app: just app-dump path/to/app.c
app-dump app=default_app target=board:
    @board="{{target}}"; \
    board="${board#boards/}"; \
    make app-dump BOARD="$board" APP="{{app}}"

# Format the design's RTL and testbenches with verible.
fmt:
    make fmt DESIGN={{design}}

# Check formatting without modifying files.
fmt-check:
    make fmt-check DESIGN={{design}}

clean:
    make clean DESIGN={{design}}
    rm -rf obj_dir riscof_work
