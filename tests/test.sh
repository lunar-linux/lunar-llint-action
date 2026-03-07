#!/usr/bin/env bash
#
# Tests for the lunar-llint-action scripts.
# Focuses on action logic: directory discovery, dedup, filtering, and runner.
#
# Usage:
#   ./tests/test.sh [path-to-llint]
#
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ACTION_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
FIXTURES="$SCRIPT_DIR/fixtures"

passed=0
failed=0
total=0

# --- Helpers ----------------------------------------------------------------

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" = "$actual" ]; then
    green "  PASS: $name"
    passed=$((passed + 1))
  else
    red "  FAIL: $name"
    red "    expected: $(echo "$expected" | head -5)"
    red "    actual:   $(echo "$actual" | head -5)"
    failed=$((failed + 1))
  fi
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  total=$((total + 1))
  if [ "$expected" -eq "$actual" ]; then
    green "  PASS: $name (exit $actual)"
    passed=$((passed + 1))
  else
    red "  FAIL: $name (expected exit $expected, got $actual)"
    failed=$((failed + 1))
  fi
}

assert_contains() {
  local name="$1" pattern="$2" output="$3"
  total=$((total + 1))
  if echo "$output" | grep -q "$pattern"; then
    green "  PASS: $name"
    passed=$((passed + 1))
  else
    red "  FAIL: $name (output missing '$pattern')"
    failed=$((failed + 1))
  fi
}

# --- Find or build llint (needed only for run-llint.sh tests) ---------------

if [ $# -ge 1 ]; then
  LLINT="$1"
elif command -v llint &>/dev/null; then
  LLINT="llint"
else
  LUNAR_LLINT="$ACTION_DIR/../lunar/tools/llint"
  if [ -f "$LUNAR_LLINT/go.mod" ]; then
    bold "Building llint from $LUNAR_LLINT ..."
    (cd "$LUNAR_LLINT" && go build -o /tmp/llint-test .)
    LLINT="/tmp/llint-test"
  else
    red "Error: llint not found. Provide a path or put it in PATH."
    exit 2
  fi
fi

bold "Using llint: $LLINT"
echo

# =============================================================================
# find-module-dirs.sh tests
# =============================================================================

bold "=== find-module-dirs.sh ==="
echo

# --- Test: deduplicates multiple files in same directory --------------------

bold "Test: dedup multiple files in same directory"
result=$(cd "$FIXTURES" && printf '%s\n' \
  "good-module/DETAILS" \
  "good-module/DEPENDS" \
  "good-module/BUILD" \
  | "$ACTION_DIR/find-module-dirs.sh")
assert_eq "3 files in one dir yields 1 dir" "good-module" "$result"
echo

# --- Test: multiple directories, each listed once ---------------------------

bold "Test: multiple directories deduplicated"
result=$(cd "$FIXTURES" && printf '%s\n' \
  "good-module/DETAILS" \
  "bad-alignment/DETAILS" \
  "good-module/DEPENDS" \
  "bad-depends/DEPENDS" \
  | "$ACTION_DIR/find-module-dirs.sh")
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert_eq "4 files across 3 dirs yields 3 dirs" "3" "$line_count"
echo

# --- Test: filters out directories without DETAILS or DEPENDS ---------------

bold "Test: filters dirs without module files"
result=$(cd "$FIXTURES" && printf '%s\n' \
  "no-module-files/README" \
  "good-module/DETAILS" \
  | "$ACTION_DIR/find-module-dirs.sh")
assert_eq "no-module-files excluded" "good-module" "$result"
echo

# --- Test: all non-module dirs yields empty output --------------------------

bold "Test: all non-module dirs yields empty output"
result=$(cd "$FIXTURES" && printf '%s\n' \
  "no-module-files/README" \
  "no-module-files/Makefile" \
  | "$ACTION_DIR/find-module-dirs.sh")
assert_eq "empty output for non-module dirs" "" "$result"
echo

# --- Test: handles nested paths correctly -----------------------------------

bold "Test: handles nested section/module paths"
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/section/mymod"
touch "$tmpdir/section/mymod/DETAILS"
result=$(cd "$tmpdir" && printf '%s\n' \
  "section/mymod/DETAILS" \
  "section/mymod/BUILD" \
  | "$ACTION_DIR/find-module-dirs.sh")
assert_eq "nested path deduplicated" "section/mymod" "$result"
rm -rf "$tmpdir"
echo

# =============================================================================
# run-llint.sh tests
# =============================================================================

bold "=== run-llint.sh ==="
echo

# --- Test: passes exit 0 for clean module -----------------------------------

bold "Test: exit 0 for clean module"
output=$(echo "$FIXTURES/good-module" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" 2>&1) && rc=0 || rc=$?
assert_exit "clean module exits 0" 0 "$rc"
echo

# --- Test: exits non-zero for bad module ------------------------------------

bold "Test: exit 1 for bad module"
output=$(echo "$FIXTURES/bad-depends" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" 2>&1) && rc=0 || rc=$?
assert_exit "bad module exits 1" 1 "$rc"
echo

# --- Test: aggregates — one bad module fails the whole run -------------------

bold "Test: mixed good+bad exits 1"
output=$(printf '%s\n' "$FIXTURES/good-module" "$FIXTURES/bad-depends" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" 2>&1) && rc=0 || rc=$?
assert_exit "mixed dirs exits 1" 1 "$rc"
assert_contains "reports bad-depends errors" "bash logic" "$output"
echo

# --- Test: all good modules exit 0 -----------------------------------------

bold "Test: multiple good modules exit 0"
output=$(printf '%s\n' "$FIXTURES/good-module" "$FIXTURES/good-module" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" 2>&1) && rc=0 || rc=$?
assert_exit "all good exits 0" 0 "$rc"
echo

# --- Test: empty input exits 0 (no dirs to lint) ---------------------------

bold "Test: empty input exits 0"
output=$(echo "" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" 2>&1) && rc=0 || rc=$?
assert_exit "empty input exits 0" 0 "$rc"
echo

# --- Test: passes extra flags through to llint ------------------------------

bold "Test: passes --max-line-length flag"
output=$(echo "$FIXTURES/good-module" \
  | "$ACTION_DIR/run-llint.sh" "$LLINT" --max-line-length 80 2>&1) && rc=0 || rc=$?
assert_exit "extra flags accepted" 0 "$rc"
echo

# --- Test: missing llint binary exits 2 ------------------------------------

bold "Test: missing llint binary fails"
output=$(echo "$FIXTURES/good-module" \
  | "$ACTION_DIR/run-llint.sh" /tmp/nonexistent-llint 2>&1) && rc=0 || rc=$?
total=$((total + 1))
if [ "$rc" -ne 0 ]; then
  green "  PASS: missing binary exits non-zero (exit $rc)"
  passed=$((passed + 1))
else
  red "  FAIL: missing binary should exit non-zero"
  failed=$((failed + 1))
fi
echo

# =============================================================================
# Summary
# =============================================================================

bold "Results: $passed/$total passed, $failed failed"
if [ "$failed" -gt 0 ]; then
  red "FAILED"
  exit 1
else
  green "ALL PASSED"
fi
