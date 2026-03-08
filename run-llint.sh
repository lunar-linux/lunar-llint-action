#!/usr/bin/env bash
#
# Runs llint on each module directory read from stdin (one per line).
#
# Usage:
#   echo "/path/to/module" | ./run-llint.sh <llint-binary> [llint-flags...]
#
# Exits non-zero if any module fails linting.
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <llint-binary> [llint-flags...]" >&2
  exit 2
fi

llint="$1"
shift

exit_code=0
failed_dirs=()
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  echo "::group::Linting $dir"
  if ! "$llint" --path "$dir" "$@"; then
    exit_code=1
    failed_dirs+=("$dir")
  fi
  echo "::endgroup::"
done

if [ "$exit_code" -ne 0 ]; then
  echo ""
  echo "❌ Lint errors found in ${#failed_dirs[@]} module(s):"
  for dir in "${failed_dirs[@]}"; do
    echo "::error::Lint failed: $dir"
    echo "  • $dir"
  done
  echo ""
  echo "Run 'llint --path <module-dir> --fix' locally to auto-fix fixable issues."
fi

exit "$exit_code"
