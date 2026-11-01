TARGET ?= tc0_sanity
SEED ?= $(shell date +%s)
ARGS ?=
JOBS ?= 4

# Extract test name if provided in ARGS (e.g. +TEST_NAME=TC1_... or TEST_NAME=TC1_...)
TEST_NAME ?= $(shell echo "$(ARGS)" | sed -n 's/.*+*TEST_NAME=\([^ ]*\).*/\1/p')
TEST_PREFIX = $(if $(TEST_NAME),$(TEST_NAME),$(TARGET))

# Output directories
LOG_DIR ?= logs
WAVE_DIR ?= waves
RTL_DIR ?= rtl
TB_DIR ?= tb
RTL_FLIST ?= $(RTL_DIR)/rtl.flist

# SV Files
TB_SV_FILES ?= $(shell find $(TB_DIR) -type f -name "*.sv" 2>/dev/null)
ALL_SV_FILES ?= $(TB_SV_FILES)

LOG_FILE ?= $(LOG_DIR)/$(TEST_PREFIX).log
WAVE_FILE ?= $(WAVE_DIR)/$(TEST_PREFIX).vcd

RC_FILE ?= .gtkwaverc

all: lint

format:
	python3 tools/lock_format.py $(TB_SV_FILES)
	-verible-verilog-format --flagfile=.verible-format --inplace $(TB_SV_FILES)

lint:
	./tools/verilator_lint.sh
	pre-commit run --config .pre-commit-config.yaml --all-files

verible-lint:
	verible-verilog-lint --rules_config=.rules.verible_lint $(TB_SV_FILES)

clean:
	rm -rf obj_dir sim.f syn/ xsim.dir/ *.pb vivado* *.jou *.log sim_output* *.vcd *.fst .Xil/ simulation.log logs waves

.PHONY: all format lint verible-lint clean
