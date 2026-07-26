cross := env_var_or_default("CROSS_COMPILE", "riscv64-none-elf-")

# Which rtl/<design> + tb/<design> pair the recipes act on.
design := env_var_or_default("DESIGN", "single_stage")

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
lint top="fpga_top":
    make lint DESIGN={{design}} TOP={{top}}

# Build and run a testbench: just sim reg_file
sim tb="fpga_top":
    make sim DESIGN={{design}} TB={{tb}}

# Run a testbench with tracing and open the VCD: just wave reg_file
wave tb="fpga_top":
    make wave DESIGN={{design}} TB={{tb}}

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

# Format the design's RTL and testbenches with verible.
fmt:
    make fmt DESIGN={{design}}

clean:
    rm -rf build obj_dir riscof_work
