#!/usr/bin/env bash
# Sunshift verification gate. Every phase must pass this before it is "done".
# Usage: ./verify.sh [--quick]
#   --quick  skip the BFS level verifier (used while levels are being authored)
set -uo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
# Kept in the repo, not in a global skills folder, so CI and a clean
# clone both run it instead of silently skipping the most useful step.
COMPILE_CHECK="tools/check_scripts_compile.gd"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

fail=0
step() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

step "1/5 import"
if ! "$GODOT" --headless --path . --import > /tmp/sunshift_import.log 2>&1; then
  echo "IMPORT FAILED"; tail -30 /tmp/sunshift_import.log; fail=1
fi

step "2/5 compile check (every .gd)"
if [ -f "$COMPILE_CHECK" ]; then
  "$GODOT" --headless --path . --script "res://$COMPILE_CHECK" || fail=1
else
  echo "MISSING: compile check script at $COMPILE_CHECK"; fail=1
fi

step "3/5 unit tests"
shopt -s nullglob
TEST_FILES=(tests/test_*.gd)
if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "WARN: no tests/test_*.gd present yet"
else
  for f in "${TEST_FILES[@]}"; do
    echo "--- $f"
    "$GODOT" --headless --path . --script "res://$f" || fail=1
  done
fi

if [ "$QUICK" = "0" ]; then
  step "4/5 level solvability (BFS)"
  if [ -f tests/verify_levels.gd ]; then
    "$GODOT" --headless --path . --script res://tests/verify_levels.gd || fail=1
  else
    echo "WARN: tests/verify_levels.gd not present yet"
  fi
else
  step "4/5 level solvability (skipped: --quick)"
fi

# Scene-based smokes: they run as real scenes because a --script runner starts
# before autoloads are registered, and everything here needs GameState.
step "5/5 scene smokes"
shopt -s nullglob
SMOKE_FILES=(tools/smoke_*.tscn)
if [ ${#SMOKE_FILES[@]} -eq 0 ]; then
  echo "WARN: no tools/smoke_*.tscn present yet"
else
  for f in "${SMOKE_FILES[@]}"; do
    echo "--- $f"
    if ! "$GODOT" --headless --path . "res://$f" > /tmp/sunshift_smoke.log 2>&1; then
      fail=1
    fi
    grep -E "RESULT:|FAIL |SCRIPT ERROR" /tmp/sunshift_smoke.log || true
    grep -q "RESULT: 0 failures" /tmp/sunshift_smoke.log || fail=1
  done
fi

printf '\n'
if [ "$fail" = "0" ]; then
  printf '\033[32mGATE PASS\033[0m\n'
else
  printf '\033[31mGATE FAIL\033[0m\n'
fi
exit "$fail"
