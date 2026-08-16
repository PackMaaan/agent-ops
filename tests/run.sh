#!/usr/bin/env bash
#
# Run every test file. Usage: tests/run.sh [name ...]
#
# Requires: git, bash 4+, jq. Nothing else.

set -uo pipefail
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v jq >/dev/null 2>&1 || { printf 'jq is required to run the test suite\n' >&2; exit 1; }

if [ $# -gt 0 ]; then
  files=()
  for name in "$@"; do
    files+=("$HERE/test_${name#test_}.sh")
  done
else
  files=("$HERE"/test_*.sh)
fi

failed=0
for f in "${files[@]}"; do
  [ -f "$f" ] || { printf 'no such test file: %s\n' "$f" >&2; failed=1; continue; }
  printf '\n'
  bash "$f" || failed=1
done

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf 'FAIL\n' >&2
  exit 1
fi
printf 'PASS\n'
