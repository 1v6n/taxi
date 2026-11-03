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

sim: $(TARGET)

prbs-check-regression:
	verilator --binary --timing -j $(JOBS) -Wall -Wno-fatal \
		--top-module tc_lfsr_prbs_check \
		$(TB_DIR)/common/lfsr_prbs_pkg.sv $(TB_DIR)/common/lfsr_prbs_check.sv \
		$(TB_DIR)/tests/common/tc_lfsr_prbs_check.sv
	./obj_dir/Vtc_lfsr_prbs_check

rx-agent-regression:
	@mkdir -p logs
	verilator --binary --timing -j $(JOBS) -Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		-Itb -Itb/common -Itb/agents --top-module tc_rx_agent_regression \
		tb/common/eth_phy_10g_tb_pkg.sv tb/common/lfsr_prbs_pkg.sv \
		tb/common/lfsr_prbs_check.sv \
		tb/agents/xgmii_rx_agent.sv tb/tests/xgmii/tc_rx_agent_regression.sv
	./obj_dir/Vtc_rx_agent_regression
	@bash -o pipefail -c 'false | tee logs/make-pipefail-test.log' >/dev/null; status=$$?; \
		if [ $$status -eq 0 ]; then echo "pipeline failure was hidden" >&2; exit 1; fi

$(TARGET):
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	verilator --binary --timing -j $(JOBS) \
		-Wall -Wno-fatal \
		-Wno-VARHIDDEN -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNDRIVEN -Wno-UNUSEDSIGNAL \
		-Wno-UNUSEDPARAM -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-ZERODLY \
		-Wno-CONSTRAINTIGN -Wno-GENUNNAMED -Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET -Wno-MULTITOP \
		-I$(RTL_DIR) -I$(TB_DIR) -I$(TB_DIR)/common -I$(TB_DIR)/agents -I$(TB_DIR)/env \
		--top-module $(TARGET) \
		-f $(RTL_FLIST) \
		$(TB_DIR)/common/eth_phy_10g_tb_pkg.sv \
		$(TB_DIR)/common/lfsr_prbs_pkg.sv \
		$(TB_DIR)/common/lfsr_prbs_check.sv \
		$(TB_DIR)/agents/xgmii_tx_agent.sv \
		$(TB_DIR)/agents/xgmii_rx_agent.sv \
		$(TB_DIR)/env/tb_env_xgmii.sv \
		$$(find $(TB_DIR)/tests -type f -name "$(TARGET).sv")
	bash -o pipefail -c './obj_dir/V$(TARGET) $(ARGS) | tee "$(LOG_FILE)"'

.PHONY: all format lint verible-lint clean sim prbs-check-regression rx-agent-regression $(TARGET)
