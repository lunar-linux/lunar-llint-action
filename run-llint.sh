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
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  echo "::group::Linting $dir"
  "$llint" --path "$dir" "$@" || exit_code=1
  echo "::endgroup::"
done

exit "$exit_code"
