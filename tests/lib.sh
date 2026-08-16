#!/usr/bin/env bash
# Minimal assertion helpers. No test framework dependency on purpose — this
# repository must be verifiable on a bare machine with git, bash, and jq.
# shellcheck shell=bash

set -uo pipefail

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  T_RED=$'\033[31m'; T_GREEN=$'\033[32m'; T_DIM=$'\033[2m'; T_RESET=$'\033[0m'
else
  T_RED=""; T_GREEN=""; T_DIM=""; T_RESET=""
fi

it() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
}

pass() { printf '  %s✓%s %s\n' "$T_GREEN" "$T_RESET" "$CURRENT_TEST"; }

failed() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  %s✗%s %s\n    %s%s%s\n' "$T_RED" "$T_RESET" "$CURRENT_TEST" "$T_DIM" "$1" "$T_RESET"
}

assert_ok() {
  if "$@" >/dev/null 2>&1; then pass; else failed "command failed: $*"; fi
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then failed "expected failure but command succeeded: $*"; else pass; fi
}

assert_eq() {
  if [ "$1" = "$2" ]; then pass; else failed "expected '$2', got '$1'"; fi
}

assert_file() {
  if [ -f "$1" ]; then pass; else failed "expected file to exist: $1"; fi
}

assert_no_file() {
  if [ ! -e "$1" ]; then pass; else failed "expected path to be absent: $1"; fi
}

assert_symlink() {
  if [ -L "$1" ]; then pass; else failed "expected a symlink: $1"; fi
}

assert_dir() {
  if [ -d "$1" ]; then pass; else failed "expected directory to exist: $1"; fi
}

assert_contains() {
  local file="$1" needle="$2"
  if [ -f "$file" ] && grep -qF "$needle" "$file"; then
    pass
  else
    failed "expected '$needle' in $file"
  fi
}

assert_not_contains() {
  local file="$1" needle="$2"
  if [ -f "$file" ] && grep -qF "$needle" "$file"; then
    failed "did not expect '$needle' in $file"
  else
    pass
  fi
}

summary() {
  printf '\n'
  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf '%s%d passed%s\n' "$T_GREEN" "$TESTS_RUN" "$T_RESET"
    return 0
  fi
  printf '%s%d of %d failed%s\n' "$T_RED" "$TESTS_FAILED" "$TESTS_RUN" "$T_RESET"
  return 1
}

# Create a throwaway git repository that plays the part of a host project.
make_host_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -b main -q
  git -C "$dir" config user.name "Test"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config commit.gpgsign false
  printf '# Host project\n\nPre-existing content that must survive.\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm "initial commit"
}
