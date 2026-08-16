#!/usr/bin/env bash
#
# Show the module registry: what is registered, whether it is checked out,
# and which skills it contributes.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

FORMAT="table"

usage() {
  cat <<'EOF'
agent-ops module list — show the module registry.

USAGE
  agent-ops module list [--json | --table]

OPTIONS
  --table   Human-readable summary (default)
  --json    Raw registry JSON, for scripting
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --table) FORMAT="table"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

ao_registry_check

if [ "$FORMAT" = "json" ]; then
  jq . "$(ao_registry_file)"
  exit 0
fi

printf '%sAgent Ops %s — module registry%s\n\n' "$C_BOLD" "$AGENT_OPS_VERSION" "$C_RESET"

jq -r '.modules[] | [.id, .kind, .path, (.enabled|tostring), .name, (.summary // ""), (.license // ""), ((.capabilities // []) | join(", "))] | @tsv' \
  "$(ao_registry_file)" |
while IFS=$'\t' read -r id kind path enabled name summary license caps; do
  state="${C_GREEN}●${C_RESET}"
  detail=""
  if [ "$enabled" != "true" ]; then
    state="${C_DIM}○${C_RESET}"
    detail="disabled"
  elif [ "$kind" = "submodule" ]; then
    if [ -e "$AO_ROOT/$path/.git" ]; then
      detail="$(git -C "$AO_ROOT/$path" rev-parse --short HEAD 2>/dev/null || echo '?')"
    else
      state="${C_YELLOW}●${C_RESET}"
      detail="not checked out"
    fi
  else
    detail="builtin"
  fi

  printf '%s %s%-18s%s %s\n' "$state" "$C_BOLD" "$id" "$C_RESET" "$name"
  printf '    %s\n' "$summary"
  printf '    %spath%s %-28s %skind%s %-10s %s%s\n' \
    "$C_DIM" "$C_RESET" "$path" "$C_DIM" "$C_RESET" "$kind" "$C_DIM" "$detail$C_RESET"
  [ -n "$license" ] && printf '    %slicense%s %s\n' "$C_DIM" "$C_RESET" "$license"
  [ -n "$caps" ] && printf '    %scaps%s %s\n' "$C_DIM" "$C_RESET" "$caps"
  printf '\n'
done

printf '%sSkills contributed%s\n' "$C_BOLD" "$C_RESET"
while IFS=$'\t' read -r module_id skill_name source; do
  mark="${C_GREEN}✓${C_RESET}"
  [ -f "$source/SKILL.md" ] || mark="${C_RED}✗${C_RESET}"
  printf '  %s %-18s %s%s%s\n' "$mark" "$skill_name" "$C_DIM" "$module_id" "$C_RESET"
done < <(ao_skills)
