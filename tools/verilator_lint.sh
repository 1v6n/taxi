#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RTL_DIR="${PROJ_DIR}/rtl"
TB_DIR="${PROJ_DIR}/tb"

cd "$PROJ_DIR"

if ! command -v verilator >/dev/null 2>&1; then
  echo "error: verilator not found in PATH" >&2
  exit 127
fi

INC_DIRS=("-I${RTL_DIR}" "-I${TB_DIR}" "-I${TB_DIR}/common" "-I${TB_DIR}/agents" "-I${TB_DIR}/env")

LINT_WAIVERS=(
  "-Wno-VARHIDDEN"
  "-Wno-WIDTHTRUNC"
  "-Wno-WIDTHEXPAND"
  "-Wno-UNDRIVEN"
  "-Wno-UNUSEDSIGNAL"
  "-Wno-UNUSEDPARAM"
  "-Wno-CASEINCOMPLETE"
  "-Wno-TIMESCALEMOD"
  "-Wno-ZERODLY"
  "-Wno-CONSTRAINTIGN"
  "-Wno-GENUNNAMED"
  "-Wno-PINCONNECTEMPTY"
  "-Wno-SYNCASYNCNET"
  "-Wno-MULTITOP"
)

echo "[Verilator Lint] Linting RTL (taxi_eth_phy_10g)..."
verilator \
  --lint-only \
  -Wall \
  -Wno-fatal \
  -sv \
  --timing \
  "${LINT_WAIVERS[@]}" \
  "${INC_DIRS[@]}" \
  --top-module taxi_eth_phy_10g \
  -f "${RTL_DIR}/rtl.flist"

echo "[Verilator Lint] Linting Testbench Common Packages..."
verilator \
  --lint-only \
  -Wall \
  -Wno-fatal \
  -sv \
  --timing \
  "${LINT_WAIVERS[@]}" \
  "${INC_DIRS[@]}" \
  "${TB_DIR}/common/eth_phy_10g_tb_pkg.sv" \
  "${TB_DIR}/common/lfsr_prbs_pkg.sv" \
  "${TB_DIR}/common/lfsr_prbs_gen.sv" \
  "${TB_DIR}/common/lfsr_prbs_check.sv" \
  "${TB_DIR}/agents/xgmii_tx_agent.sv" \
  "${TB_DIR}/agents/xgmii_rx_agent.sv"

echo "[Verilator Lint] Linting Testbench Environment & Tests (tc0_sanity)..."
verilator \
  --lint-only \
  -Wall \
  -Wno-fatal \
  -sv \
  --timing \
  "${LINT_WAIVERS[@]}" \
  "${INC_DIRS[@]}" \
  --top-module tc0_sanity \
  -f "${RTL_DIR}/rtl.flist" \
  "${TB_DIR}/common/eth_phy_10g_tb_pkg.sv" \
  "${TB_DIR}/common/lfsr_prbs_pkg.sv" \
  "${TB_DIR}/common/lfsr_prbs_check.sv" \
  "${TB_DIR}/agents/xgmii_tx_agent.sv" \
  "${TB_DIR}/agents/xgmii_rx_agent.sv" \
  "${TB_DIR}/env/tb_env_xgmii.sv" \
  "${TB_DIR}/tests/xgmii/tc0_sanity.sv"

echo "[Verilator Lint] Clean."
