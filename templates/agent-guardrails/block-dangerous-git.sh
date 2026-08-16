#!/usr/bin/env bash
#
# PreToolUse guardrail: refuse destructive git commands issued by an agent.
#
# Installed by `agent-ops bootstrap --guardrails` and wired into
# .claude/settings.json as a Bash PreToolUse hook.
#
# Contract with the harness:
#   stdin     the tool-call payload as JSON
#   exit 0    allow the command
#   exit 2    block it; stderr is shown to the agent as the reason
#
# What this is and is not. It stops an agent from *casually* running a
# history-destroying command — the class of mistake that happens when a model
# reaches for `git reset --hard` to "clean up". It is not a security boundary:
# anything that can run `bash -c` defeats it. Treat it as a seatbelt, and keep
# the real protection on the server side, where branch protection lives.

set -euo pipefail

payload="$(cat)"

# Read .tool_input.command with jq when available; fall back to a narrow sed so
# the hook still functions on a machine without jq.
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || printf '')"
else
  cmd="$(printf '%s' "$payload" \
    | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

[ -n "$cmd" ] || exit 0

# Classify one command segment. Empty output means "allowed".
# Patterns are anchored at the start of the segment, so a command merely
# *mentioning* one of these — echo "never run git push --force" — is not blocked.
classify() {
  case "$1" in
    "git push --force"*|"git push -f"*)                                printf 'force push' ;;
    "git push"*)                                                       printf 'push' ;;
    "git reset --hard"*)                                               printf 'hard reset' ;;
    "git clean "*-*f*)                                                 printf 'working tree wipe' ;;
    "git branch -D"*|"git branch --delete --force"*)                   printf 'force branch delete' ;;
    "git checkout ."|"git checkout -- ."|"git restore ."|"git restore -- .") printf 'discard all local changes' ;;
    "git rebase"*)                                                     printf 'rebase' ;;
    "git filter-branch"*|"git filter-repo"*)                           printf 'history rewrite' ;;
    "git update-ref -d"*)                                              printf 'ref deletion' ;;
    *) ;;
  esac
}

# A guardrail that inspects only the first command is bypassed by `true; git push`,
# so every segment of a compound command is checked. Splitting on ; && || | and
# newlines is coarse — it also splits inside quoted strings — but erring toward
# *more* segments only ever makes the check stricter.
segments="$(printf '%s' "$cmd" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g')"

hit=""
segment=""
while IFS= read -r raw; do
  segment="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$segment" ] || continue
  hit="$(classify "$segment")"
  [ -n "$hit" ] && break
done <<EOF
$segments
EOF

if [ -n "$hit" ]; then
  {
    printf 'BLOCKED by repository guardrails: %s\n\n' "$hit"
    printf '  %s\n\n' "$segment"
    printf 'Destructive git operations are not available to agent-driven Bash.\n'
    printf 'If this is genuinely required, run it yourself outside the agent, or\n'
    printf 'remove the hook from .claude/settings.json deliberately.\n'
  } >&2
  exit 2
fi

exit 0
