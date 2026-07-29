# RTL build/sim driver.
#
# Parameterised by DESIGN so later variants (multicycle, pipelined, ...) drop in
# as new rtl/<DESIGN> + tb/<DESIGN> directories with no Makefile changes, and by
# TB so each module can be simulated against its own standalone testbench.
#
#   make lint                  # lint the whole design (top = core)
#   make lint TOP=reg_file     # lint one module standalone
#   make sim  TB=reg_file      # build + run tb/<design>/tb_reg_file.sv
#   make wave TB=reg_file      # same, with a VCD, opened in GTKWave
#   make DESIGN=multicycle ...

DESIGN ?= single_stage
TOP    ?= core
BOARD  ?= lfe5um5g_85f_evn

# Which testbench to build and run: tb/<DESIGN>/tb_<TB>.sv
TB     ?= $(TOP)
TB_TOP := tb_$(TB)

RTL_DIR    := rtl/$(DESIGN)
TB_DIR     := tb/$(DESIGN)
BUILD_ROOT := build/$(DESIGN)
SIM_DIR    := $(BUILD_ROOT)/$(TB_TOP)

# Packages must be compiled before anything that imports them. Plain
# alphabetical globbing would place riscv_pkg.sv after extend.sv and friends and
# fail elaboration with "Reference to 'word_t' before declaration", so *_pkg.sv
# is pulled out and placed first.
PKG_SRCS := $(sort $(wildcard $(RTL_DIR)/*_pkg.sv))
RTL_SRCS := $(PKG_SRCS) \
            $(filter-out $(PKG_SRCS), \
              $(sort $(wildcard $(RTL_DIR)/*.sv) $(wildcard $(RTL_DIR)/*.v)))
TB_SRC   := $(TB_DIR)/$(TB_TOP).sv
SRCS     := $(RTL_SRCS) $(TB_SRC)

BOARD_DIR       := rtl/boards/$(BOARD)
BOARD_SIM_SRC_DIR := sim/boards/$(BOARD)
BOARD_TOP       ?= top
BOARD_SIM       ?= top_sim
BOARD_SIM_TOP   := $(BOARD_SIM)
BOARD_BUILD_DIR := build/boards/$(BOARD)
BOARD_SIM_BUILD_DIR := $(BOARD_BUILD_DIR)/sim/$(BOARD_SIM_TOP)
BOARD_LOCAL_SRCS := $(sort $(wildcard $(BOARD_DIR)/*.sv) $(wildcard $(BOARD_DIR)/*.v))
BOARD_SRCS       := $(RTL_SRCS) $(BOARD_LOCAL_SRCS)
BOARD_SIM_SRC    := $(BOARD_SIM_SRC_DIR)/$(BOARD_SIM_TOP).sv
BOARD_SIM_HARNESS_SRCS := $(BOARD_SRCS) $(BOARD_SIM_SRC)
BOARD_LPF       := $(BOARD_DIR)/pins.lpf
BOARD_JSON      := $(BOARD_BUILD_DIR)/$(BOARD_TOP).json
BOARD_CONFIG    := $(BOARD_BUILD_DIR)/$(BOARD_TOP).config
BOARD_BIT       := $(BOARD_BUILD_DIR)/$(BOARD_TOP).bit
BOARD_PROGRAM   ?= led_skip
BOARD_PROGRAM_SRC := $(BOARD_DIR)/programs/$(BOARD_PROGRAM).S

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
BOARD_INCLUDE := boards/$(BOARD)/include

APP ?= $(BOARD_PROGRAM_SRC)
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

RISCV_ARCH ?= rv32i
RISCV_ABI  ?= ilp32
IMEM_BYTES ?= 2048
DMEM_BYTES ?= 2048

APP_COMMON_FLAGS := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
                    -ffreestanding -nostdlib -nostartfiles \
                    -fno-builtin -Wall -Wextra -Os \
                    -I$(SDK_INCLUDE) -I$(BOARD_INCLUDE)
APP_CFLAGS       ?= $(APP_COMMON_FLAGS) -std=c11
APP_CXXFLAGS     ?= $(APP_COMMON_FLAGS) -std=c++20 -fno-exceptions -fno-rtti -fno-use-cxa-atexit
APP_ASFLAGS      ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI)
APP_LDFLAGS      ?= -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) \
                    -nostdlib -nostartfiles -Wl,--gc-sections \
                    -Wl,--defsym=ImemBytes=$(IMEM_BYTES) \
                    -Wl,--defsym=DmemBytes=$(DMEM_BYTES) \
                    -T $(SDK_LINKER)
APP_LINK         := $(if $(APP_CXX_SRCS),$(RISCV_GXX),$(RISCV_GCC))

ECP5_DEVICE  ?= --um5g-85k
ECP5_PACKAGE ?= CABGA381
ECP5_SPEED   ?= 8
ECP5_FREQ    ?= 12

# Every testbench/simulator in the design — for formatting only. Simulation
# compiles just the one selected by TB, so sibling top-level modules don't
# collide.
ALL_TB_SRCS := $(sort $(wildcard $(TB_DIR)/*.sv) $(wildcard $(TB_DIR)/*.v))
ALL_SIM_SRCS := $(sort $(wildcard sim/boards/*/*.sv) $(wildcard sim/boards/*/*.v))

VERILATOR ?= verilator
VERILATOR_FLAGS := -sv --timing --assert -Wall -I$(RTL_DIR) -I$(TB_DIR)
BOARD_SIM_VERILATOR_FLAGS := -sv --timing --assert -Wall \
                              -I$(RTL_DIR) -I$(BOARD_DIR) -I$(BOARD_SIM_SRC_DIR)

# Set TRACE=1 to build with waveform support and dump a VCD.
ifeq ($(TRACE),1)
  VERILATOR_FLAGS += --trace
  RUN_ARGS += +trace
endif

SIM_BIN := $(SIM_DIR)/V$(TB_TOP)
BOARD_HARNESS_BIN := $(BOARD_SIM_BUILD_DIR)/V$(BOARD_SIM_TOP)

.PHONY: all lint sim run wave fmt fmt-check filelist app-build app-dump board-sim board-run board-program board-synth board-pnr board-pack board-build board-flash clean help
.DEFAULT_GOAL := help

all: sim

## lint: Verilator lint of the RTL, no testbench (override TOP for one module)
lint: $(RTL_SRCS)
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module $(TOP) $(RTL_SRCS)

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
             --formal_parameters_indentation=indent \
             --named_port_indentation=indent \
             --named_parameter_indentation=indent

fmt:
	verible-verilog-format --inplace $(FMT_FLAGS) $(RTL_SRCS) $(ALL_TB_SRCS) $(ALL_SIM_SRCS)

## fmt-check: fail if anything is not formatted (no files modified)
fmt-check:
	@fail=0; for f in $(RTL_SRCS) $(ALL_TB_SRCS) $(ALL_SIM_SRCS); do \
		verible-verilog-format $(FMT_FLAGS) "$$f" | diff -q - "$$f" >/dev/null 2>&1 \
			|| { echo "needs formatting: $$f"; fail=1; }; \
	done; exit $$fail

## filelist: regenerate verible.filelist (language server cross-file symbols)
# Without this file verible-verilog-ls only sees the buffer being edited, so
# types from riscv_pkg read as "Can't find typedef". Packages are listed first.
filelist:
	@{ find rtl tb sim -name '*_pkg.sv' 2>/dev/null | sort; \
	   find rtl tb sim \( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) \
	        ! -name '*_pkg.sv' 2>/dev/null | sort; } > verible.filelist
	@echo "verible.filelist: $$(wc -l < verible.filelist) files"

$(APP_BUILD_DIR)/%.S.o: %.S
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(APP_ASFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.c.o: %.c
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GCC) $(APP_CFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.cc.o: %.cc
	@test -f $< || { echo "no such app source: $<"; exit 1; }
	@mkdir -p $(dir $@)
	$(RISCV_GXX) $(APP_CXXFLAGS) -c $< -o $@

$(APP_BUILD_DIR)/%.cpp.o: %.cpp
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
	$(RISCV_OBJCOPY) -O binary -j .text $< $@

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
		-GImemInitFile=\"$(abspath $(APP_MEM))\" \
		--Mdir $(BOARD_SIM_BUILD_DIR) \
		-o V$(BOARD_SIM_TOP) \
		$(BOARD_SIM_HARNESS_SRCS)

board-run: $(BOARD_HARNESS_BIN)
	cd $(BOARD_SIM_BUILD_DIR) && ./V$(BOARD_SIM_TOP) $(RUN_ARGS)

## board-sim: build and run a board-level testbench
board-sim: board-run

## board-program: build the selected APP into a readmemh file
board-program: app-build

$(BOARD_JSON): $(BOARD_SRCS) $(APP_MEM)
	@test -n "$(BOARD_SRCS)" || { echo "no board sources found in $(BOARD_DIR)"; exit 1; }
	@mkdir -p $(BOARD_BUILD_DIR)
	yosys -p 'read_verilog -sv $(BOARD_SRCS); chparam -set ImemInitFile "$(APP_MEM)" $(BOARD_TOP); synth_ecp5 -top $(BOARD_TOP) -json $@'

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
