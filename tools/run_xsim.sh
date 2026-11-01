#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULE_ROOT="$(cd "${VERIF_DIR}/.." && pwd)"
RTL_DIR="${MODULE_ROOT}/design/rtl"

cd "$VERIF_DIR"

STAGE="${STAGE:-5}"
TARGET="${1:-tb_top}"
shift || true

TB_DIR="${VERIF_DIR}/stage_${STAGE}"
TB_FILE="${TB_DIR}/${TARGET}.sv"

if [ ! -f "$TB_FILE" ]; then
  echo "error: testbench file '$TB_FILE' not found." >&2
  exit 1
fi

TOP="$TARGET"

# Locate Vivado / XSim toolchain
locate_tool() {
  local tool_name="$1"
  if command -v "$tool_name" >/dev/null 2>&1; then
    command -v "$tool_name"
    return 0
  fi
  for p in /tools/Xilinx/Vivado/*/bin /opt/Xilinx/Vivado/*/bin /tools/Xilinx/*/Vivado/bin; do
    if [[ -x "$p/$tool_name" ]]; then
      echo "$p/$tool_name"
      return 0
    fi
  done
  return 1
}

XVLOG_BIN="$(locate_tool xvlog || true)"
XELAB_BIN="$(locate_tool xelab || true)"
XSIM_BIN="$(locate_tool xsim || true)"

if [[ -z "$XVLOG_BIN" || -z "$XELAB_BIN" || -z "$XSIM_BIN" ]]; then
  echo "Error: XSim toolchain (xvlog, xelab, xsim) not found in PATH or standard Xilinx directories." >&2
  echo "Please ensure Vivado settings are sourced (e.g. 'source <vivado_dir>/settings64.sh')." >&2
  exit 127
fi

SNAPSHOT="${TOP}_snapshot"

INC_DIRS=("-i" "${RTL_DIR}" "-i" "${TB_DIR}")
TB_FILES=()

if [ -f "${TB_DIR}/tb.flist" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" || "$line" =~ ^// || "$line" =~ ^# ]] && continue
    if [[ "$line" =~ ^-incdir[[:space:]]+(.*) ]]; then
      INC_DIRS+=("-i" "${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^\+incdir\+(.*) ]]; then
      INC_DIRS+=("-i" "${BASH_REMATCH[1]}")
    else
      TB_FILES+=("$line")
    fi
  done < "${TB_DIR}/tb.flist"
else
  for f in "${TB_DIR}"/serial_to_parallel_intf.sv "${TB_DIR}"/serial_to_parallel_sequence_item.sv "${TB_DIR}"/serial_to_parallel_driver.sv "${TB_DIR}"/serial_to_parallel_monitor.sv; do
    if [ -f "$f" ]; then
      TB_FILES+=("$f")
    fi
  done
  TB_FILES+=("$TB_FILE")
fi

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "Compiling with xvlog (stage $STAGE)..."
  "$XVLOG_BIN" -sv -nolog "${INC_DIRS[@]}" "${RTL_DIR}"/*.sv "${TB_FILES[@]}"

  echo "Elaborating snapshot $SNAPSHOT with xelab..."
  "$XELAB_BIN" -timescale 1ns/1ps -debug typical -nolog -s "$SNAPSHOT" "$TOP"
fi

if [ "${BUILD_ONLY:-0}" = "1" ]; then
  echo "Build complete."
  exit 0
fi

# Convert plusargs (+ARG=VAL to -testplusarg ARG=VAL)
XSIM_ARGS=()
for arg in "$@"; do
  if [[ "$arg" =~ ^\+(.*) ]]; then
    XSIM_ARGS+=("-testplusarg" "${BASH_REMATCH[1]}")
  else
    XSIM_ARGS+=("$arg")
  fi
done

echo "Running simulation with xsim..."
"$XSIM_BIN" "$SNAPSHOT" -R -nosignalhandlers -nolog "${XSIM_ARGS[@]}"
