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
BOARD_TOP       ?= top
BOARD_BUILD_DIR := build/boards/$(BOARD)
BOARD_LOCAL_SRCS := $(sort $(wildcard $(BOARD_DIR)/*.sv) $(wildcard $(BOARD_DIR)/*.v))
BOARD_SRCS       := $(RTL_SRCS) $(BOARD_LOCAL_SRCS)
BOARD_LPF       := $(BOARD_DIR)/pins.lpf
BOARD_JSON      := $(BOARD_BUILD_DIR)/$(BOARD_TOP).json
BOARD_CONFIG    := $(BOARD_BUILD_DIR)/$(BOARD_TOP).config
BOARD_BIT       := $(BOARD_BUILD_DIR)/$(BOARD_TOP).bit
BOARD_PROGRAM   ?= led_skip
BOARD_PROGRAM_SRC := $(BOARD_DIR)/programs/$(BOARD_PROGRAM).S
BOARD_PROGRAM_OBJ := $(BOARD_BUILD_DIR)/$(BOARD_PROGRAM).o
BOARD_PROGRAM_BIN := $(BOARD_BUILD_DIR)/$(BOARD_PROGRAM).bin
BOARD_PROGRAM_MEM := $(BOARD_BUILD_DIR)/$(BOARD_PROGRAM).mem

CROSS_COMPILE ?= riscv64-none-elf-
RISCV_GCC     ?= $(CROSS_COMPILE)gcc
RISCV_OBJCOPY ?= $(CROSS_COMPILE)objcopy

ECP5_DEVICE  ?= --um5g-85k
ECP5_PACKAGE ?= CABGA381
ECP5_SPEED   ?= 8
ECP5_FREQ    ?= 12

# Every testbench in the design — for formatting only. Simulation compiles just
# the one selected by TB, so that sibling testbenches don't collide as extra
# top-level modules.
ALL_TB_SRCS := $(sort $(wildcard $(TB_DIR)/*.sv) $(wildcard $(TB_DIR)/*.v))

VERILATOR ?= verilator
VERILATOR_FLAGS := -sv --timing --assert -Wall -I$(RTL_DIR) -I$(TB_DIR)

# Set TRACE=1 to build with waveform support and dump a VCD.
ifeq ($(TRACE),1)
  VERILATOR_FLAGS += --trace
  RUN_ARGS += +trace
endif

SIM_BIN := $(SIM_DIR)/V$(TB_TOP)

.PHONY: all lint sim run wave fmt fmt-check filelist board-program board-synth board-pnr board-pack board-build board-flash clean help
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
	verible-verilog-format --inplace $(FMT_FLAGS) $(RTL_SRCS) $(ALL_TB_SRCS)

## fmt-check: fail if anything is not formatted (no files modified)
fmt-check:
	@fail=0; for f in $(RTL_SRCS) $(ALL_TB_SRCS); do \
		verible-verilog-format $(FMT_FLAGS) "$$f" | diff -q - "$$f" >/dev/null 2>&1 \
			|| { echo "needs formatting: $$f"; fail=1; }; \
	done; exit $$fail

## filelist: regenerate verible.filelist (language server cross-file symbols)
# Without this file verible-verilog-ls only sees the buffer being edited, so
# types from riscv_pkg read as "Can't find typedef". Packages are listed first.
filelist:
	@{ find rtl tb -name '*_pkg.sv' 2>/dev/null | sort; \
	   find rtl tb \( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) \
	        ! -name '*_pkg.sv' 2>/dev/null | sort; } > verible.filelist
	@echo "verible.filelist: $$(wc -l < verible.filelist) files"

$(BOARD_PROGRAM_OBJ): $(BOARD_PROGRAM_SRC)
	@test -f $< || { echo "no such board program: $<"; exit 1; }
	@mkdir -p $(BOARD_BUILD_DIR)
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -c $< -o $@

$(BOARD_PROGRAM_BIN): $(BOARD_PROGRAM_OBJ)
	$(RISCV_OBJCOPY) -O binary -j .text $< $@

$(BOARD_PROGRAM_MEM): $(BOARD_PROGRAM_BIN)
	od -An -v -tx4 -w4 $< | tr -d ' ' > $@

## board-program: assemble the selected board program into a readmemh file
board-program: $(BOARD_PROGRAM_MEM)

$(BOARD_JSON): $(BOARD_SRCS) $(BOARD_PROGRAM_MEM)
	@test -n "$(BOARD_SRCS)" || { echo "no board sources found in $(BOARD_DIR)"; exit 1; }
	@mkdir -p $(BOARD_BUILD_DIR)
	yosys -p 'read_verilog -sv $(BOARD_SRCS); chparam -set ImemInitFile "$(BOARD_PROGRAM_MEM)" $(BOARD_TOP); synth_ecp5 -top $(BOARD_TOP) -json $@'

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
