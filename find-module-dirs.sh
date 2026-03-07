#!/usr/bin/env bash
#
# Finds unique module directories (containing DETAILS or DEPENDS) from a list
# of changed files. Reads file paths from stdin, one per line.
#
# Usage:
#   git diff --name-only BASE HEAD | ./find-module-dirs.sh
#
set -euo pipefail

xargs -I{} dirname {} \
  | sort -u \
  | while read -r d; do
      [ -f "$d/DETAILS" ] || [ -f "$d/DEPENDS" ] && echo "$d"
    done || true
