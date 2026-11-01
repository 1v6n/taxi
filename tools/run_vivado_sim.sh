#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$VERIF_DIR"

# Default values
MODE="batch"
TCL_SCRIPT="tools/run_vivado_sim.tcl"
SEED=""
ARGS=""
STAGE="${STAGE:-0}"
TARGET="${TARGET:-tb_top}"
PROJECT_ONLY=0
NO_AUTORUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -p, --project-only       Open Vivado GUI with project loaded (without launching simulation)
  -g, --gui                Run Vivado in GUI mode (default: batch mode)
  --no-run, --pause        In GUI mode, launch simulation paused at 0ns (do not run all immediately)
  -s, --seed <seed>        Specify random simulation seed
  --stage <stage_num>      Specify stage number (default: 0)
  --top <module_name>      Specify top testbench module (default: tb_top)
  -a, --args <args>        Additional simulator arguments (e.g. +VERBOSE=1)
  -t, --tcl <script>       Custom TCL script to run (default: tools/run_vivado_sim.tcl)
  -h, --help               Show this help message
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--proj|--project-only)
      MODE="gui"
      PROJECT_ONLY=1
      shift
      ;;
    -g|--gui)
      MODE="gui"
      shift
      ;;
    --no-run|--pause)
      NO_AUTORUN=1
      shift
      ;;
    -s|--seed)
      SEED="$2"
      shift 2
      ;;
    --stage)
      STAGE="$2"
      shift 2
      ;;
    --top)
      TARGET="$2"
      shift 2
      ;;
    -a|--args)
      ARGS="$2"
      shift 2
      ;;
    -t|--tcl)
      TCL_SCRIPT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Locate Vivado executable
VIVADO_BIN=""
if command -v vivado >/dev/null 2>&1; then
  VIVADO_BIN="vivado"
else
  for p in /tools/Xilinx/Vivado/*/bin/vivado /opt/Xilinx/Vivado/*/bin/vivado /tools/Xilinx/*/Vivado/bin/vivado; do
    if [[ -x "$p" ]]; then
      VIVADO_BIN="$p"
      break
    fi
  done
fi

if [[ -z "$VIVADO_BIN" ]]; then
  echo "Error: 'vivado' executable not found in PATH or standard installation directories (/tools/Xilinx, /opt/Xilinx)." >&2
  echo "Please ensure Vivado environment settings are sourced (e.g., 'source <vivado_install_dir>/settings64.sh')." >&2
  exit 127
fi

# Export environment variables for the TCL script
export STAGE
export TARGET
[[ -n "$SEED" ]] && export SEED
[[ -n "$ARGS" ]] && export ARGS
[[ "$PROJECT_ONLY" -eq 1 ]] && export PROJECT_ONLY
[[ "$NO_AUTORUN" -eq 1 ]] && export NO_AUTORUN

echo "========================================"
if [[ "$PROJECT_ONLY" -eq 1 ]]; then
  echo "Opening Vivado Project GUI"
else
  echo "Running Vivado Simulation"
fi
echo "Target: $TARGET (Stage $STAGE)"
echo "Mode: $MODE"
echo "TCL Script: $TCL_SCRIPT"
[[ -n "$SEED" ]] && echo "Seed: $SEED"
[[ -n "$ARGS" ]] && echo "Simulator Args: $ARGS"
[[ "$NO_AUTORUN" -eq 1 ]] && echo "Auto-run: disabled (paused at 0ns)"
echo "========================================"

"$VIVADO_BIN" -mode "$MODE" -source "$TCL_SCRIPT"

