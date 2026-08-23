# RTL build/sim driver.
#
# Parameterised by DESIGN so later variants (multicycle, pipelined, ...) drop in
# as new rtl/cpu/<DESIGN> + tb/<DESIGN> directories with no Makefile changes, and
# by TB so each module can be simulated against its own standalone testbench.
#
#   make lint                  # lint the whole design (top = core)
#   make lint TOP=reg_file     # lint one module standalone
#   make sim  TB=reg_file      # build + run the matching mirrored testbench
#   make wave TB=reg_file      # same, with a VCD, opened in GTKWave
#   make DESIGN=multicycle ...

DESIGN ?= pipelined
TOP    ?= soc

DEFAULT_BOARD     := lfe5um5g_85f_evn
DEFAULT_SIM_BOARD := sim
DEFAULT_SIM_APP   := examples/apps/uart_halt_c

ifneq ($(filter board-sim board-run board-app-test,$(MAKECMDGOALS)),)
BOARD ?= $(DEFAULT_SIM_BOARD)
else
BOARD ?= $(DEFAULT_BOARD)
endif

# Which testbench to build and run: tb/<DESIGN>/tb_<TB>.sv
TB     ?= $(TOP)
TB_TOP := tb_$(TB)

RTL_LIB_DIR    := rtl/lib
RTL_PERIPH_DIR := rtl/periph
CPU_LIB_DIR    := rtl/cpu/lib
CPU_DESIGN_DIR := rtl/cpu/$(DESIGN)
TB_DIR         := tb/cpu/$(DESIGN)
TB_COMMON_DIR  := tb/cpu/$(DESIGN)/common
CPU_LIB_TB_DIR := tb/cpu/lib
RTL_LIB_TB_DIR := tb/lib
PERIPH_TB_DIR  := tb/periph
BUILD_ROOT    := build/$(DESIGN)
SIM_DIR       := $(BUILD_ROOT)/$(TB_TOP)

# Packages must be compiled before anything that imports them. Plain
# alphabetical globbing would place riscv_pkg.sv after extend.sv and friends and
# fail elaboration with "Reference to 'word_t' before declaration", so *_pkg.sv
# is pulled out and placed first.
CPU_PKG_SRCS := $(sort $(wildcard $(CPU_LIB_DIR)/*_pkg.sv) $(wildcard $(CPU_DESIGN_DIR)/*_pkg.sv))
RTL_LIB_SRCS := $(sort $(wildcard $(RTL_LIB_DIR)/*.sv) $(wildcard $(RTL_LIB_DIR)/*.v))
CPU_LIB_SRCS := $(filter-out $(CPU_PKG_SRCS), \
                  $(sort $(wildcard $(CPU_LIB_DIR)/*.sv) $(wildcard $(CPU_LIB_DIR)/*.v)))
CPU_DESIGN_SRCS := $(filter-out $(CPU_PKG_SRCS), \
                    $(sort $(wildcard $(CPU_DESIGN_DIR)/*.sv) $(wildcard $(CPU_DESIGN_DIR)/*.v)))
PERIPH_SRCS := $(sort $(wildcard $(RTL_PERIPH_DIR)/*.sv) $(wildcard $(RTL_PERIPH_DIR)/*.v))
RTL_SRCS := $(CPU_PKG_SRCS) $(RTL_LIB_SRCS) $(CPU_LIB_SRCS) $(CPU_DESIGN_SRCS)
TB_SRC   := $(firstword $(wildcard $(TB_DIR)/$(TB_TOP).sv \
                            $(CPU_LIB_TB_DIR)/$(TB_TOP).sv \
                            $(RTL_LIB_TB_DIR)/$(TB_TOP).sv \
                            $(PERIPH_TB_DIR)/$(TB_TOP).sv))
# Shared testbench helpers, compiled into every simulation of this design.
TB_COMMON_SRCS := $(sort $(wildcard $(TB_COMMON_DIR)/*.sv))
SRCS     := $(RTL_SRCS) $(PERIPH_SRCS) $(TB_COMMON_SRCS) $(TB_SRC)

BOARD_DIR       := boards/$(BOARD)
BOARD_RTL_DIR   := $(BOARD_DIR)/rtl
BOARD_SIM_SRC_DIR := $(BOARD_DIR)/sim
BOARD_TOP       ?= top
BOARD_SIM       ?= top_sim
BOARD_SIM_TOP   := $(BOARD_SIM)
BOARD_BUILD_DIR := build/boards/$(BOARD)
BOARD_SIM_BUILD_DIR = $(BOARD_BUILD_DIR)/sim/$(DESIGN)/$(BOARD_SIM_TOP)/$(APP_NAME)
BOARD_TB_DIR       := tb/boards/$(BOARD)
BOARD_TB           ?= timer_mmio
BOARD_TB_TOP       := tb_$(BOARD_TB)
BOARD_TB_SRC       := $(BOARD_TB_DIR)/$(BOARD_TB_TOP).sv
BOARD_TB_BUILD_DIR := $(BOARD_BUILD_DIR)/tb/$(BOARD_TB_TOP)
BOARD_PKG_SRCS    := $(sort $(wildcard $(BOARD_RTL_DIR)/*_pkg.sv))
BOARD_LOCAL_SRCS := $(BOARD_PKG_SRCS) \
                    $(filter-out $(BOARD_PKG_SRCS), \
                      $(sort $(wildcard $(BOARD_RTL_DIR)/*.sv) $(wildcard $(BOARD_RTL_DIR)/*.v)))
BOARD_SRCS       := $(RTL_SRCS) $(PERIPH_SRCS) $(BOARD_LOCAL_SRCS)
BOARD_SIM_SRC    := $(BOARD_SIM_SRC_DIR)/$(BOARD_SIM_TOP).sv
BOARD_SIM_HARNESS_SRCS := $(BOARD_SRCS) $(BOARD_SIM_SRC)
BOARD_LPF       := $(BOARD_RTL_DIR)/pins.lpf
BOARD_JSON      := $(BOARD_BUILD_DIR)/$(BOARD_TOP).json
BOARD_CONFIG    := $(BOARD_BUILD_DIR)/$(BOARD_TOP).config
BOARD_BIT       := $(BOARD_BUILD_DIR)/$(BOARD_TOP).bit
BOARD_PROGRAM   ?= led_skip
BOARD_PROGRAM_SRC := $(BOARD_RTL_DIR)/programs/$(BOARD_PROGRAM).S

CROSS_COMPILE ?= riscv64-none-elf-
RISCV_GCC     ?= $(CROSS_COMPILE)gcc
RISCV_GXX     ?= $(CROSS_COMPILE)g++
RISCV_OBJCOPY ?= $(CROSS_COMPILE)objcopy
RISCV_OBJDUMP ?= $(CROSS_COMPILE)objdump
RISCV_SIZE    ?= $(CROSS_COMPILE)size

SDK_DIR      := sdk/riscv32
SDK_LINKER   := $(SDK_DIR)/link.ld
SDK_CRT0_SRC := $(SDK_DIR)/crt0.S
SDK_INCLUDE  := $(SDK_DIR)/include
BOARD_INCLUDE := $(BOARD_DIR)/include
APP_HEADER_DEPS := $(shell find $(SDK_INCLUDE) $(BOARD_INCLUDE) -type f -name '*.h' 2>/dev/null)
BOARD_CONSTANTS      := $(BOARD_DIR)/board_constants.yml
BOARD_CONSTANTS_HDR  := $(BOARD_INCLUDE)/board_constants.h
BOARD_CONSTANTS_PKG  := $(BOARD_RTL_DIR)/board_constants_pkg.sv
COMPILE_COMMANDS  := compile_commands.json

ifneq ($(filter board-sim board-run board-app-test,$(MAKECMDGOALS)),)
APP ?= $(DEFAULT_SIM_APP)
else
APP ?= $(BOARD_PROGRAM_SRC)
endif
APP_IS_DIR := $(shell test -d "$(APP)" && echo 1)
ifeq ($(APP_IS_DIR),1)
APP_NAME := $(notdir $(patsubst %/,%,$(APP)))
APP_SRCS := $(sort $(wildcard $(APP)/*.S) \
                   $(wildcard $(APP)/*.c) \
                   $(wildcard $(APP)/*.cc) \
                   $(wildcard $(APP)/*.cpp))
else
APP_NAME := $(notdir $(basename $(APP)))
APP_SRCS := $(APP)
endif

APP_BUILD_DIR := $(BOARD_BUILD_DIR)/apps/$(APP_NAME)
APP_OBJS      := $(addsuffix .o,$(addprefix $(APP_BUILD_DIR)/,$(APP_SRCS)))
APP_CXX_SRCS  := $(filter %.cc %.cpp,$(APP_SRCS))
APP_HIGH_SRCS := $(filter %.c %.cc %.cpp,$(APP_SRCS))
APP_CRT0_OBJ  := $(APP_BUILD_DIR)/$(SDK_CRT0_SRC).o
APP_START_OBJS := $(if $(APP_HIGH_SRCS),$(APP_CRT0_OBJ))
APP_ELF       := $(APP_BUILD_DIR)/$(APP_NAME).elf
APP_BIN       := $(APP_BUILD_DIR)/$(APP_NAME).bin
APP_MEM       := $(APP_BUILD_DIR)/$(APP_NAME).mem
APP_DUMP      := $(APP_BUILD_DIR)/$(APP_NAME).dump

# Zicsr is a separate extension from binutils 2.38 onward; the core implements
# the CSR instructions, so name it explicitly or `csrrw` and friends fail to
# assemble.
RISCV_ARCH ?= rv32i_zicsr
RISCV_ABI  ?= ilp32
MEM_BYTES ?= 4096

APP_COMMON_FLAGS := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
                    -ffreestanding -nostdlib -nostartfiles \
                    -fno-builtin -Wall -Wextra -Os \
                    -I$(SDK_INCLUDE) -I$(BOARD_INCLUDE)
APP_CFLAGS       ?= $(APP_COMMON_FLAGS) -std=c11
APP_CXXFLAGS     ?= $(APP_COMMON_FLAGS) -std=c++20 -fno-exceptions -fno-rtti -fno-use-cxa-atexit
APP_ASFLAGS      ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI)
APP_LDFLAGS      ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
                    -nostdlib -nostartfiles -Wl,--gc-sections \
                    -Wl,--defsym=MemBytes=$(MEM_BYTES) \
                    -T $(SDK_LINKER)
APP_LINK         := $(if $(APP_CXX_SRCS),$(RISCV_GXX),$(RISCV_GCC))

ECP5_DEVICE  ?= --um5g-85k
ECP5_PACKAGE ?= CABGA381
ECP5_SPEED   ?= 8
ECP5_FREQ    ?= 12
MIN_DP16KD   ?= 8

# Every testbench/simulator in the design — for formatting only. Simulation
# compiles just the one selected by TB, so sibling top-level modules don't
# collide.
ALL_TB_SRCS := $(sort $(wildcard $(TB_DIR)/*.sv) $(wildcard $(TB_DIR)/*.v) \
                       $(wildcard $(TB_COMMON_DIR)/*.sv) \
                       $(wildcard $(CPU_LIB_TB_DIR)/*.sv) $(wildcard $(CPU_LIB_TB_DIR)/*.v) \
                       $(wildcard $(RTL_LIB_TB_DIR)/*.sv) $(wildcard $(RTL_LIB_TB_DIR)/*.v) \
                       $(wildcard $(PERIPH_TB_DIR)/*.sv) $(wildcard $(PERIPH_TB_DIR)/*.v))
ALL_BOARD_TB_SRCS := $(sort $(wildcard tb/boards/*/*.sv) $(wildcard tb/boards/*/*.v))
ALL_BOARD_SRCS := $(sort $(wildcard boards/*/rtl/*.sv) $(wildcard boards/*/rtl/*.v) \
                         $(wildcard boards/*/sim/*.sv) $(wildcard boards/*/sim/*.v))

VERILATOR ?= verilator
VERILATOR_FLAGS := -sv --timing --assert -Wall -Werror-IMPLICIT \
                   -I$(RTL_LIB_DIR) -I$(CPU_LIB_DIR) -I$(CPU_DESIGN_DIR) \
                   -I$(TB_DIR) -I$(CPU_LIB_TB_DIR) -I$(RTL_LIB_TB_DIR)
BOARD_SIM_VERILATOR_FLAGS := -sv --timing --assert -Wall -Werror-IMPLICIT \
                              -I$(RTL_LIB_DIR) -I$(RTL_PERIPH_DIR) \
                              -I$(CPU_LIB_DIR) -I$(CPU_DESIGN_DIR) \
                              -I$(BOARD_RTL_DIR) -I$(BOARD_SIM_SRC_DIR)
YOSYS ?= yosys
YOSYS_FLAGS := -m slang
YOSYS_READ := read_slang --ignore-assertions

# Set TRACE=1 to build with waveform support and dump a VCD.
ifeq ($(TRACE),1)
  VERILATOR_FLAGS += --trace
  RUN_ARGS += +trace
endif

SIM_BIN := $(SIM_DIR)/V$(TB_TOP)
BOARD_HARNESS_BIN := $(BOARD_SIM_BUILD_DIR)/V$(BOARD_SIM_TOP)
BOARD_TB_BIN := $(BOARD_TB_BUILD_DIR)/V$(BOARD_TB_TOP)

.PHONY: all lint style sim run wave fmt fmt-check filelist compile-commands board-constants app-build app-dump board-sim board-run board-app-test board-tb board-tb-run board-program board-synth board-pnr board-pack board-build board-flash clean help FORCE
.DEFAULT_GOAL := help

all: sim

## lint: Verilator lint of the RTL, no testbench (override TOP for one module)
lint: $(RTL_SRCS)
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module $(TOP) $(RTL_SRCS)

## style: project-specific SystemVerilog naming/style checks
style:
	tools/check_sv_style.py $(RTL_SRCS) $(PERIPH_SRCS) $(ALL_TB_SRCS) $(ALL_BOARD_TB_SRCS) $(ALL_BOARD_SRCS)

## sim: build and run the testbench selected by TB
sim: run

$(SIM_BIN): $(SRCS)
	@test -f $(TB_SRC) || { echo "no such testbench: $(TB_SRC)"; exit 1; }
	@mkdir -p $(SIM_DIR)
	$(VERILATOR) --binary $(VERILATOR_FLAGS) \
		--top-module $(TB_TOP) \
		--Mdir $(SIM_DIR) \
		-o V$(TB_TOP) \
		$(SRCS)

run: $(SIM_BIN)
	cd $(SIM_DIR) && ./V$(TB_TOP) $(RUN_ARGS)

## wave: run with tracing and open the resulting VCD in GTKWave
wave:
	$(MAKE) run TRACE=1
	gtkwave $(SIM_DIR)/dump.vcd

## fmt: format all of the design's RTL and testbenches in place
# verible defaults to "wrap" for port/parameter lists and named instance
# connections, which indents continuation lines by 4 spaces. This design
# indents them by one level like everything else, so set each family to "indent".
FMT_FLAGS := --port_declarations_indentation=indent \
             --port_declarations_alignment=align \
             --formal_parameters_indentation=indent \
             --formal_parameters_alignment=align \
             --named_port_indentation=indent \
             --named_port_alignment=preserve \
             --named_parameter_indentation=indent \
             --named_parameter_alignment=preserve \
             --module_net_variable_alignment=align

fmt:
	verible-verilog-format --inplace $(FMT_FLAGS) $(RTL_SRCS) $(PERIPH_SRCS) $(ALL_TB_SRCS) $(ALL_BOARD_TB_SRCS) $(ALL_BOARD_SRCS)

## fmt-check: fail if anything is not formatted (no files modified)
fmt-check:
	@fail=0; for f in $(RTL_SRCS) $(PERIPH_SRCS) $(ALL_TB_SRCS) $(ALL_BOARD_TB_SRCS) $(ALL_BOARD_SRCS); do \
		verible-verilog-format $(FMT_FLAGS) "$$f" | diff -q - "$$f" >/dev/null 2>&1 \
			|| { echo "needs formatting: $$f"; fail=1; }; \
	done; exit $$fail

$(BOARD_CONSTANTS_HDR) $(BOARD_CONSTANTS_PKG) &: $(BOARD_CONSTANTS) tools/gen_board_constants.py
	tools/gen_board_constants.py $< --c-header $(BOARD_CONSTANTS_HDR) --sv-package $(BOARD_CONSTANTS_PKG)

## board-constants: regenerate the selected board's generated constants files
board-constants: $(BOARD_CONSTANTS_HDR) $(BOARD_CONSTANTS_PKG)

## filelist: list slang-server build filelists
# slang-server reads .slang/server.json, which points at the checked-in build
# filelists under .slang/builds. Each filelist is design-specific because
# different CPU design directories define the same module names, such as `core`.
filelist:
	@ls .slang/builds/*.f

$(COMPILE_COMMANDS): FORCE tools/gen_compile_commands.py $(BOARD_CONSTANTS_HDR)
	tools/gen_compile_commands.py --board $(BOARD) --output $@

## compile-commands: regenerate compile_commands.json for clangd
compile-commands: $(COMPILE_COMMANDS)

$(APP_BUILD_DIR)/%.S.o: %.S $(BOARD_CONSTANTS_HDR)
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(APP_ASFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.c.o: %.c $(APP_HEADER_DEPS)
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(APP_CFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.cc.o: %.cc $(APP_HEADER_DEPS)
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GXX) $(APP_CXXFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.cpp.o: %.cpp $(APP_HEADER_DEPS)
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GXX) $(APP_CXXFLAGS) -c $< -o $@

$(APP_CRT0_OBJ): $(SDK_CRT0_SRC)
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(APP_ASFLAGS) -c $< -o $@

$(APP_ELF): $(APP_START_OBJS) $(APP_OBJS) $(SDK_LINKER)
	@test -n "$(APP_SRCS)" || { echo "no app sources found: $(APP)"; exit 1; }
	@mkdir -p $(APP_BUILD_DIR)
	NIX_HARDENING_ENABLE= $(APP_LINK) $(APP_LDFLAGS) $(APP_START_OBJS) $(APP_OBJS) -o $@
	$(RISCV_SIZE) $@

$(APP_BIN): $(APP_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(APP_MEM): $(APP_BIN)
	od -An -v -tx4 -w4 $< | tr -d ' ' > $@

$(APP_DUMP): $(APP_ELF)
	$(RISCV_OBJDUMP) -d -S $< > $@

## app-build: build APP into ELF/bin/readmemh outputs
app-build: $(APP_MEM)

## app-dump: disassemble APP into build/.../<app>.dump
app-dump: $(APP_DUMP)

$(BOARD_HARNESS_BIN): $(BOARD_SIM_HARNESS_SRCS) $(APP_MEM)
	@test -f $(BOARD_SIM_SRC) || { echo "no such board simulator: $(BOARD_SIM_SRC)"; exit 1; }
	@mkdir -p $(BOARD_SIM_BUILD_DIR)
	$(VERILATOR) --binary $(BOARD_SIM_VERILATOR_FLAGS) \
		--top-module $(BOARD_SIM_TOP) \
		-GMemInitFile=\"$(abspath $(APP_MEM))\" \
		-GMemDepthWords=$(shell expr $(MEM_BYTES) / 4) \
		--Mdir $(BOARD_SIM_BUILD_DIR) \
		-o V$(BOARD_SIM_TOP) \
		$(BOARD_SIM_HARNESS_SRCS)

board-run: $(BOARD_HARNESS_BIN)
	cd $(BOARD_SIM_BUILD_DIR) && ./V$(BOARD_SIM_TOP) $(RUN_ARGS)

## board-sim: build and run a board-level testbench
board-sim: board-run

## board-app-test: run simulated-board firmware regressions
board-app-test:
	tools/run_board_app_tests.py --design $(DESIGN) --board $(BOARD) --sim $(BOARD_SIM)

$(BOARD_TB_BIN): $(BOARD_SRCS) $(BOARD_TB_SRC)
	@test -f $(BOARD_TB_SRC) || { echo "no such board testbench: $(BOARD_TB_SRC)"; exit 1; }
	@mkdir -p $(BOARD_TB_BUILD_DIR)
	$(VERILATOR) --binary $(BOARD_SIM_VERILATOR_FLAGS) \
		--top-module $(BOARD_TB_TOP) \
		--Mdir $(BOARD_TB_BUILD_DIR) \
		-o V$(BOARD_TB_TOP) \
		$(BOARD_SRCS) $(BOARD_TB_SRC)

board-tb-run: $(BOARD_TB_BIN)
	cd $(BOARD_TB_BUILD_DIR) && ./V$(BOARD_TB_TOP) $(RUN_ARGS)

## board-tb: build and run a board peripheral testbench
board-tb: board-tb-run

## board-program: build the selected APP into a readmemh file
board-program: app-build

$(BOARD_JSON): $(BOARD_SRCS) $(APP_MEM) $(BOARD_CONSTANTS_PKG)
	@test -n "$(BOARD_SRCS)" || { echo "no board sources found in $(BOARD_DIR)"; exit 1; }
	@mkdir -p $(BOARD_BUILD_DIR)
	$(YOSYS) $(YOSYS_FLAGS) -p '$(YOSYS_READ) --top $(BOARD_TOP) -G MemInitFile="$(APP_MEM)" $(BOARD_SRCS); synth_ecp5 -top $(BOARD_TOP) -json $@'
	tools/check_bram.py $@ --minimum $(MIN_DP16KD)

$(BOARD_CONFIG): $(BOARD_JSON) $(BOARD_LPF)
	nextpnr-ecp5 $(ECP5_DEVICE) --package $(ECP5_PACKAGE) --speed $(ECP5_SPEED) \
		--freq $(ECP5_FREQ) \
		--json $< \
		--lpf $(BOARD_LPF) \
		--textcfg $@

$(BOARD_BIT): $(BOARD_CONFIG)
	ecppack --compress $< $@

## board-synth: synthesize the selected board top with Yosys
board-synth: $(BOARD_JSON)
	tools/check_bram.py $(BOARD_JSON) --minimum $(MIN_DP16KD)

## board-pnr: place and route the selected ECP5 board design
board-pnr: $(BOARD_CONFIG)

## board-build: build a bitstream for the selected board
board-build: $(BOARD_BIT)

## board-flash: program the selected board bitstream into FPGA SRAM
board-flash: $(BOARD_BIT)
	openFPGALoader -m $<

## clean: remove this design's build directory
clean:
	rm -rf $(BUILD_ROOT) build/boards

help:
	@echo "targets (DESIGN=$(DESIGN), TB=$(TB)):"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
