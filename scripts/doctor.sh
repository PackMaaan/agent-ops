#!/usr/bin/env bash
#
# Diagnose the Agent Ops environment: tooling, registry validity, submodule
# checkout state, and whether the host repository is actually wired up.
#
# Exit code 0 = healthy, 1 = at least one hard failure.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET=""
FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
agent-ops doctor — diagnose the environment and installed state.

USAGE
  agent-ops doctor [--target DIR]

Exits non-zero if anything is broken. Warnings (optional tooling, unconfigured
host) do not fail the run.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

check_fail() { fail "$*"; FAILURES=$((FAILURES + 1)); }
check_warn() { warn "$*"; WARNINGS=$((WARNINGS + 1)); }

# --- tooling ----------------------------------------------------------------

info "tooling"
if have git; then ok "git $(git --version | awk '{print $3}')"; else check_fail "git is not installed"; fi
if have jq; then ok "jq $(jq --version 2>/dev/null | sed 's/^jq-//')"; else check_fail "jq is not installed (required to read the module registry)"; fi

if have gh; then
  ok "gh $(gh --version 2>/dev/null | head -1 | awk '{print $3}')"
  if gh auth status >/dev/null 2>&1; then
    ok "gh authenticated"
  else
    check_warn "gh is not authenticated — run 'gh auth login' before bootstrap"
  fi
else
  check_warn "gh is not installed — 'agent-ops bootstrap' and the ccpm sync phase need it"
fi

if gh extension list 2>/dev/null | grep -q 'gh-sub-issue'; then
  ok "gh-sub-issue extension present"
else
  check_warn "gh-sub-issue not installed — CCPM falls back to task lists. Install: gh extension install yahsan2/gh-sub-issue"
fi

for opt in shellcheck actionlint yamllint markdownlint-cli2; do
  if have "$opt"; then ok "$opt (optional) present"; else skip "$opt (optional) not installed"; fi
done

# --- registry ---------------------------------------------------------------

info "module registry"
reg=$(ao_registry_file)
if jq -e . "$reg" >/dev/null 2>&1; then
  ok "valid JSON: $(ao_relpath "$reg" "$AO_ROOT")"
else
  check_fail "registry is not valid JSON: $reg"
fi

if [ "$reg" != "$AO_REGISTRY" ]; then
  check_warn "using local overlay registry — tracked modules.json is being ignored"
fi

# Every registry entry must have a matching .gitmodules entry, and vice versa.
if [ "$FAILURES" -eq 0 ]; then
  while IFS=$'\t' read -r id kind path _name; do
    if [ "$kind" = "submodule" ]; then
      if git -C "$AO_ROOT" config -f .gitmodules --get "submodule.$path.url" >/dev/null 2>&1; then
        ok "$id: declared in .gitmodules"
      else
        check_fail "$id: registry path '$path' has no .gitmodules entry"
      fi
    fi
  done < <(ao_modules)

  while read -r path; do
    [ -n "$path" ] || continue
    if ! jq -e --arg p "$path" '.modules[] | select(.path == $p)' "$reg" >/dev/null 2>&1; then
      check_fail "submodule '$path' exists in .gitmodules but is not in the registry"
    fi
  done < <(git -C "$AO_ROOT" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
fi

# --- module checkouts -------------------------------------------------------

info "module checkouts"
while IFS=$'\t' read -r id kind path name; do
  if [ "$kind" = "builtin" ]; then
    skip "$id (builtin)"
    continue
  fi
  if [ ! -e "$AO_ROOT/$path/.git" ]; then
    check_fail "$id: not checked out — run 'git submodule update --init --recursive'"
    continue
  fi
  sha=$(git -C "$AO_ROOT/$path" rev-parse --short HEAD 2>/dev/null || echo "?")
  dirty=""
  git -C "$AO_ROOT/$path" diff --quiet 2>/dev/null || dirty=" ${C_YELLOW}(dirty)${C_RESET}"
  ok "$id @ $sha$dirty — $name"
done < <(ao_modules)

# --- skills -----------------------------------------------------------------

info "skills"
while IFS=$'\t' read -r module_id skill_name source; do
  if [ -f "$source/SKILL.md" ]; then
    ok "$skill_name (from $module_id)"
  else
    check_fail "$skill_name: no SKILL.md at $source"
  fi
done < <(ao_skills)

# --- host repository --------------------------------------------------------

info "host repository"
[ -n "$TARGET" ] && AGENT_OPS_HOST="$TARGET"
export AGENT_OPS_HOST="${AGENT_OPS_HOST:-}"

if host=$(ao_host_root 2>/dev/null); then
  ok "detected: $host"
  if slug=$(ao_host_slug "$host" 2>/dev/null); then
    ok "origin: $slug"
  else
    check_warn "no GitHub 'origin' remote — 'agent-ops bootstrap' will only write local files"
  fi

  linked=0
  while IFS=$'\t' read -r _module_id skill_name source; do
    for dest_rel in .claude/skills .agents/skills .factory/skills .opencode/skills; do
      link="$host/$dest_rel/$skill_name"
      if ao_link_matches "$link" "$source"; then
        ok "$dest_rel/$skill_name linked"
        linked=$((linked + 1))
      elif [ -d "$link" ]; then
        ok "$dest_rel/$skill_name present (copied)"
        linked=$((linked + 1))
      fi
    done
  done < <(ao_skills)
  [ "$linked" -eq 0 ] && check_warn "no skills installed yet — run 'agent-ops install'"
else
  check_warn "Agent Ops is not inside a host repository (standalone checkout)"
fi

# --- summary ----------------------------------------------------------------

printf '\n' >&2
if [ "$FAILURES" -gt 0 ]; then
  printf '%s%d failure(s), %d warning(s)%s\n' "$C_RED" "$FAILURES" "$WARNINGS" "$C_RESET" >&2
  exit 1
fi
printf '%shealthy%s — %d warning(s)\n' "$C_GREEN" "$C_RESET" "$WARNINGS" >&2
