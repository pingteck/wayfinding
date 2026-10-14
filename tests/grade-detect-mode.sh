#!/usr/bin/env bash
# Set-equality gate for detect-mode.sh output. Catches missing / extra / swapped-shape units.
set -uo pipefail
FIX="${1:?usage: grade-detect-mode.sh <fixture-name> <detect-output-file> <expected-mode>}"
OUT="${2:?missing detect-output-file}"
EXP_MODE="${3:?missing expected-mode}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SET="$DIR/expected-sets/$FIX.set"
fail=0

# mode check
actual_mode="$(grep -E '^mode=' "$OUT" | head -1 | sed 's/^mode=//')"
[ "$actual_mode" = "$EXP_MODE" ] || { echo "MISS: mode=$actual_mode, expected $EXP_MODE"; fail=1; }

# unit-set equality (shape + path), order-independent
actual_units="$(grep -E '^unit ' "$OUT" | sed -E 's/^unit //' | sort)"
expected_units="$(sort "$SET")"
if [ "$actual_units" != "$expected_units" ]; then
  echo "MISS: unit set mismatch for $FIX"
  # name extras / missing precisely
  comm -13 <(printf '%s\n' "$expected_units") <(printf '%s\n' "$actual_units") | sed 's/^/  EXTRA:   /'
  comm -23 <(printf '%s\n' "$expected_units") <(printf '%s\n' "$actual_units") | sed 's/^/  MISSING: /'
  fail=1
fi

[ "$fail" = 0 ] && echo "DETECT OK" || echo "DETECT FAILED"
exit $fail
