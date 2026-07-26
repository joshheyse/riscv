# RTL build/sim driver.
#
# Parameterised by DESIGN so later variants (multicycle, pipelined, ...) drop in
# as new rtl/<DESIGN> + tb/<DESIGN> directories with no Makefile changes, and by
# TB so each module can be simulated against its own standalone testbench.
#
#   make lint                  # lint the whole design (top = fpga_top)
#   make lint TOP=reg_file     # lint one module standalone
#   make sim  TB=reg_file      # build + run tb/<design>/tb_reg_file.sv
#   make wave TB=reg_file      # same, with a VCD, opened in GTKWave
#   make DESIGN=multicycle ...

DESIGN ?= single_stage
TOP    ?= fpga_top

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

.PHONY: all lint sim run wave fmt clean help
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

## clean: remove this design's build directory
clean:
	rm -rf $(BUILD_ROOT)

help:
	@echo "targets (DESIGN=$(DESIGN), TB=$(TB)):"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
