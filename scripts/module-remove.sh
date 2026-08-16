#!/usr/bin/env bash
#
# Deregister a module: drop its registry entry and remove the git submodule,
# including the .git/modules cache that `git rm` leaves behind.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ID=""
DRY_RUN=0
KEEP_FILES=0

usage() {
  cat <<'EOF'
agent-ops module remove — deregister a module and drop its submodule.

USAGE
  agent-ops module remove ID [options]

OPTIONS
  --keep-files   Remove the registry entry but leave the submodule in place
  --dry-run      Print what would change and exit
  -h, --help     Show this message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-files) KEEP_FILES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) ID="$1"; shift ;;
  esac
done

[ -n "$ID" ] || { usage >&2; die "module id is required"; }
require_jq
ao_registry_check

ao_module_exists "$ID" || die "module '$ID' is not registered"
kind=$(ao_module_field "$ID" kind)
[ "$kind" = "builtin" ] && die "'$ID' is a builtin module and cannot be removed"
mod_path=$(ao_module_field "$ID" path)

info "removing module '$ID' at $mod_path"

if [ "$DRY_RUN" -eq 1 ]; then
  would "remove registry entry '$ID'"
  [ "$KEEP_FILES" -eq 0 ] && would "git submodule deinit + rm $mod_path"
  would "remove skill links from the host repository"
  exit 0
fi

# Unlink from the host first, while the registry still describes the skills.
if host=$(ao_host_root 2>/dev/null); then
  while IFS=$'\t' read -r module_id skill_name source; do
    [ "$module_id" = "$ID" ] || continue
    for dest_rel in .claude/skills .agents/skills .factory/skills .opencode/skills; do
      link="$host/$dest_rel/$skill_name"
      if ao_link_matches "$link" "$source"; then
        rm -f "$link"
        ok "unlinked $dest_rel/$skill_name"
      fi
    done
  done < <(ao_skills)
fi

tmp="$AO_REGISTRY.tmp"
jq --arg id "$ID" 'del(.modules[] | select(.id == $id))' "$AO_REGISTRY" >"$tmp"
mv "$tmp" "$AO_REGISTRY"
ok "registry entry removed"

if [ "$KEEP_FILES" -eq 0 ]; then
  git -C "$AO_ROOT" submodule deinit -f "$mod_path" >/dev/null 2>&1 || warn "deinit failed (already gone?)"
  git -C "$AO_ROOT" rm -f "$mod_path" >/dev/null 2>&1 || warn "git rm failed (already gone?)"
  rm -rf "${AO_ROOT:?}/.git/modules/$mod_path"
  ok "submodule removed"
else
  skip "submodule left in place (--keep-files)"
fi

info "done — review the diff, update NOTICE.md, then commit"
