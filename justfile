cross := env_var_or_default("CROSS_COMPILE", "riscv64-none-elf-")

# Cross-compile the smoke test and run it on both ISA simulators.
smoke:
    mkdir -p build
    {{cross}}gcc -march=rv64i -mabi=lp64 -nostdlib -nostartfiles \
        -T sw/smoke/link.ld sw/smoke/smoke.S -o build/smoke.elf
    spike build/smoke.elf && echo "spike: PASS"
    sail_riscv_sim build/smoke.elf > build/sail.log && echo "sail:  PASS"

# Lint RTL with Verilator (add files under rtl/ first).
lint:
    verilator --lint-only -Wall rtl/*.sv

fmt:
    verible-verilog-format --inplace rtl/*.sv tb/*.sv

clean:
    rm -rf build obj_dir riscof_work
