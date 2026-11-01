#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULE_ROOT="$(cd "${VERIF_DIR}/.." && pwd)"
RTL_DIR="${MODULE_ROOT}/design/rtl"

cd "$VERIF_DIR"

STAGE="${STAGE:-5}"
TARGET="${1:-tb_top}"

TB_DIR="${VERIF_DIR}/stage_${STAGE}"
TB_FILE="${TB_DIR}/${TARGET}.sv"

if [ ! -f "$TB_FILE" ]; then
  echo "error: testbench file '$TB_FILE' not found." >&2
  echo "Looking for '${TARGET}.sv' inside stage_${STAGE}/" >&2
  exit 1
fi

TOP="$TARGET"

echo "Compiling $TOP (stage $STAGE)..."

if command -v nproc >/dev/null 2>&1; then
  CORES=$(nproc)
elif command -v sysctl >/dev/null 2>&1; then
  CORES=$(sysctl -n hw.ncpu)
else
  CORES=1
fi

INC_DIRS=("-I${RTL_DIR}" "-I${TB_DIR}")
TB_FILES=()

if [ -f "${TB_DIR}/tb.flist" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" || "$line" =~ ^// || "$line" =~ ^# ]] && continue
    if [[ "$line" =~ ^-incdir[[:space:]]+(.*) ]]; then
      INC_DIRS+=("-I${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^\+incdir\+(.*) ]]; then
      INC_DIRS+=("-I${BASH_REMATCH[1]}")
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

EXTRA_FLAGS=()
if [ "$STAGE" -ge 2 ] 2>/dev/null; then
  EXTRA_FLAGS+=("--assert")
fi

WAIVER_FLAGS=(
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
)

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  CURRENT_VERILATOR_VER="$(verilator --version 2>/dev/null || true)"
  if [ -d "obj_dir" ]; then
    CACHED_VERILATOR_VER="$(cat obj_dir/.verilator_version 2>/dev/null || true)"
    if [ -n "$CURRENT_VERILATOR_VER" ] && [ "$CURRENT_VERILATOR_VER" != "$CACHED_VERILATOR_VER" ]; then
      echo "Verilator environment changed ($CACHED_VERILATOR_VER -> $CURRENT_VERILATOR_VER). Cleaning obj_dir..."
      rm -rf obj_dir
    fi
  fi

  verilator --binary --trace-fst --timing "${EXTRA_FLAGS[@]}" -j "$CORES" \
    -Wall \
    -Wno-fatal \
    "${WAIVER_FLAGS[@]}" \
    -CFLAGS "-Wno-unknown-warning-option" \
    "${INC_DIRS[@]}" \
    --top-module "$TOP" \
    "${RTL_DIR}"/*.sv \
    "${TB_FILES[@]}"

  if [ -d "obj_dir" ]; then
    echo "$CURRENT_VERILATOR_VER" > obj_dir/.verilator_version
  fi
fi

if [ "${BUILD_ONLY:-0}" = "1" ]; then
  echo "Build complete."
  exit 0
fi

echo "Running simulation..."
shift || true
"./obj_dir/V$TOP" "$@"
