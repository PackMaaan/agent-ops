#!/usr/bin/env bash
#
# The destructive-git PreToolUse hook. A guardrail that is registered but does
# not block is worse than none — it reads as protection while allowing
# everything — so its behaviour is asserted, not assumed.
#
# Contract: exit 2 blocks the command, exit 0 allows it.

set -uo pipefail
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

printf 'guardrail hook\n'

HOOK="$ROOT/templates/agent-guardrails/block-dangerous-git.sh"

it "the hook exists"
assert_file "$HOOK"

# run <command> -> prints the hook's exit code
run() {
  printf '{"tool_input":{"command":"%s"}}' "$1" | bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$?"
}

blocks() {
  it "blocks: $1"
  assert_eq "$(run "$1")" "2"
}

allows() {
  it "allows: $1"
  assert_eq "$(run "$1")" "0"
}

# --- must block -------------------------------------------------------------

blocks "git push origin main"
blocks "git push --force origin main"
blocks "git push -f"
blocks "git reset --hard HEAD~1"
blocks "git clean -fd"
blocks "git clean -xdf"
blocks "git branch -D feature"
blocks "git checkout ."
blocks "git restore ."
blocks "git rebase -i main"
blocks "git filter-branch --tree-filter true HEAD"
blocks "git update-ref -d refs/heads/main"

# A guardrail that inspects only the first command is trivially bypassed.
blocks "true; git push origin main"
blocks "npm test && git push"
blocks "false || git reset --hard"
blocks "echo hi | git push"

# --- must allow -------------------------------------------------------------

allows "git status"
allows "git log --oneline -5"
allows "git diff --stat"
allows "git add -A"
allows "git commit -m 'feat: something'"
allows "git fetch origin"
allows "git checkout -b feature/new"
allows "git branch -d merged-branch"
allows "ls -la"
allows "npm test"

# Mentioning a dangerous command is not running one.
allows "echo never run git push --force"

# --- malformed input --------------------------------------------------------

it "allows an empty payload rather than failing closed on noise"
printf '%s' '{}' | bash "$HOOK" >/dev/null 2>&1
assert_eq "$?" "0"

it "allows a payload with no command field"
printf '%s' '{"tool_input":{}}' | bash "$HOOK" >/dev/null 2>&1
assert_eq "$?" "0"

it "explains itself on stderr when it blocks"
msg=$(printf '{"tool_input":{"command":"git push origin main"}}' | bash "$HOOK" 2>&1 >/dev/null)
case "$msg" in
  *BLOCKED*) pass ;;
  *) failed "expected 'BLOCKED' in stderr, got: $msg" ;;
esac

summary
