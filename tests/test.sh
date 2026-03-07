#!/usr/bin/env bash
#
# Local test suite for the lunar-llint GitHub Action.
#
# Usage:
#   ./tests/test.sh [path-to-llint]
#
# If no path is given, it looks for llint in PATH or builds it from
# the lunar repo at ../lunar/tools/llint.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FIXTURES="$SCRIPT_DIR/fixtures"

passed=0
failed=0
total=0

# --- Helpers ----------------------------------------------------------------

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

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

assert_output_contains() {
  local name="$1" pattern="$2" output="$3"
  total=$((total + 1))
  if echo "$output" | grep -q "$pattern"; then
    green "  PASS: $name (output contains '$pattern')"
    passed=$((passed + 1))
  else
    red "  FAIL: $name (output missing '$pattern')"
    failed=$((failed + 1))
  fi
}

assert_output_not_contains() {
  local name="$1" pattern="$2" output="$3"
  total=$((total + 1))
  if ! echo "$output" | grep -q "$pattern"; then
    green "  PASS: $name (output does not contain '$pattern')"
    passed=$((passed + 1))
  else
    red "  FAIL: $name (output unexpectedly contains '$pattern')"
    failed=$((failed + 1))
  fi
}

# --- Find or build llint ----------------------------------------------------

if [ $# -ge 1 ]; then
  LLINT="$1"
elif command -v llint &>/dev/null; then
  LLINT="llint"
else
  LUNAR_LLINT="$SCRIPT_DIR/../../lunar/tools/llint"
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

# --- Test: good module passes -----------------------------------------------

bold "Test: good module should pass with no errors"
output=$("$LLINT" --path "$FIXTURES/good-module" 2>&1) && rc=0 || rc=$?
assert_exit "good-module exits 0" 0 "$rc"
assert_output_not_contains "good-module no error output" "error:" "$output"
echo

# --- Test: bad alignment is detected ----------------------------------------

bold "Test: bad alignment should report errors"
output=$("$LLINT" --path "$FIXTURES/bad-alignment" 2>&1) && rc=0 || rc=$?
assert_exit "bad-alignment exits 1" 1 "$rc"
assert_output_contains "bad-alignment reports alignment" "not aligned" "$output"
assert_output_contains "bad-alignment reports missing blank line" "blank line before heredoc" "$output"
echo

# --- Test: bad alignment is fixable -----------------------------------------

bold "Test: bad alignment should be fixable"
tmpdir=$(mktemp -d)
cp -r "$FIXTURES/bad-alignment/"* "$tmpdir/"
output=$("$LLINT" --path "$tmpdir" --fix --verbose 2>&1) && rc=0 || rc=$?
assert_exit "bad-alignment --fix exits 0" 0 "$rc"
assert_output_contains "bad-alignment --fix reports fixes" "fixed:" "$output"

# Verify fixed file passes
output=$("$LLINT" --path "$tmpdir" 2>&1) && rc=0 || rc=$?
assert_exit "bad-alignment after fix passes" 0 "$rc"
rm -rf "$tmpdir"
echo

# --- Test: bad DEPENDS is detected ------------------------------------------

bold "Test: bad DEPENDS should report errors"
output=$("$LLINT" --path "$FIXTURES/bad-depends" 2>&1) && rc=0 || rc=$?
assert_exit "bad-depends exits 1" 1 "$rc"
assert_output_contains "bad-depends reports bash logic" "bash logic" "$output"
echo

# --- Test: bad DEPENDS is NOT fixable ----------------------------------------

bold "Test: bad DEPENDS errors should remain after --fix"
tmpdir=$(mktemp -d)
cp -r "$FIXTURES/bad-depends/"* "$tmpdir/"
output=$("$LLINT" --path "$tmpdir" --fix 2>&1) && rc=0 || rc=$?
assert_exit "bad-depends --fix still exits 1" 1 "$rc"
assert_output_contains "bad-depends --fix still reports bash logic" "bash logic" "$output"
rm -rf "$tmpdir"
echo

# --- Test: directory with no module files ------------------------------------

bold "Test: directory with no module files should pass"
output=$("$LLINT" --path "$FIXTURES/no-module-files" 2>&1) && rc=0 || rc=$?
assert_exit "no-module-files exits 0" 0 "$rc"
echo

# --- Test: --path with invalid directory ------------------------------------

bold "Test: --path with nonexistent directory should fail"
output=$("$LLINT" --path "/tmp/nonexistent-module-dir" 2>&1) && rc=0 || rc=$?
assert_exit "nonexistent dir exits 2" 2 "$rc"
echo

# --- Test: dir-dedup simulation ----------------------------------------------

bold "Test: directory deduplication logic"
# Simulate the dedup logic from the action
changed_files="zlocal/testmod/DETAILS
zlocal/testmod/DEPENDS
zlocal/testmod/BUILD
zlocal/other/DETAILS"

dirs=$(echo "$changed_files" \
  | xargs -I{} dirname {} \
  | sort -u)

expected="zlocal/other
zlocal/testmod"

total=$((total + 1))
if [ "$dirs" = "$expected" ]; then
  green "  PASS: dedup produces 2 unique dirs from 4 files"
  passed=$((passed + 1))
else
  red "  FAIL: dedup expected 2 dirs, got: $dirs"
  failed=$((failed + 1))
fi
echo

# --- Summary ----------------------------------------------------------------

bold "Results: $passed/$total passed, $failed failed"
if [ "$failed" -gt 0 ]; then
  red "FAILED"
  exit 1
else
  green "ALL PASSED"
fi
