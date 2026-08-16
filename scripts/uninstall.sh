#!/usr/bin/env bash
#
# Remove everything `agent-ops install` created in the host repository.
# Only removes symlinks Agent Ops owns and the managed instruction blocks —
# host-authored files are never touched.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

DRY_RUN=0
TARGET=""
PURGE=0
EXTRA_DESTS=""   # newline-delimited, appended to the default harness locations

usage() {
  cat <<'EOF'
agent-ops uninstall — remove installed skills and managed blocks.

USAGE
  agent-ops uninstall [options]

OPTIONS
  --target DIR   Host repository root (default: auto-detected superproject)
  --dest DIR     Additional skills directory to clean, relative to the host.
                 Repeatable. The four standard harness locations are always
                 checked; pass this for anything installed with --dest.
  --purge        Also remove copied (non-symlink) skill directories
  --dry-run      Print what would change and exit
  -h, --help     Show this message

By default only symlinks created by `agent-ops install` are removed. Directories
created with `--copy` are left alone unless you pass --purge, because they may
have been edited in place.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    --dest) EXTRA_DESTS="${EXTRA_DESTS}${2:?--dest needs a directory}"$'\n'; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

DESTS=".claude/skills
.agents/skills
.factory/skills
.opencode/skills
${EXTRA_DESTS}"

[ -n "$TARGET" ] && AGENT_OPS_HOST="$TARGET"
export AGENT_OPS_HOST="${AGENT_OPS_HOST:-}"
HOST=$(ao_require_host_root)

info "host repository: $HOST"
[ "$DRY_RUN" -eq 1 ] && warn "dry run — no changes will be written"

removed=0
while IFS= read -r dest_rel; do
  [ -n "$dest_rel" ] || continue
  dest="$HOST/$dest_rel"
  [ -d "$dest" ] || continue
  while IFS=$'\t' read -r _module_id skill_name source; do
    link="$dest/$skill_name"
    [ -e "$link" ] || [ -L "$link" ] || continue

    if [ -L "$link" ]; then
      if ao_link_matches "$link" "$source"; then
        if [ "$DRY_RUN" -eq 1 ]; then would "remove $dest_rel/$skill_name"; else rm -f "$link"; ok "removed $dest_rel/$skill_name"; fi
        removed=$((removed + 1))
      else
        skip "$dest_rel/$skill_name is a symlink Agent Ops does not own — left in place"
      fi
    elif [ "$PURGE" -eq 1 ]; then
      if [ "$DRY_RUN" -eq 1 ]; then would "remove copied $dest_rel/$skill_name"; else rm -rf "$link"; ok "removed copied $dest_rel/$skill_name"; fi
      removed=$((removed + 1))
    else
      warn "$dest_rel/$skill_name is a real directory — re-run with --purge to remove it"
    fi
  done < <(ao_skills)

  # Clean up the skills directory if Agent Ops created it and it is now empty.
  if [ "$DRY_RUN" -eq 0 ] && [ -d "$dest" ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
    rmdir "$dest" 2>/dev/null || true
  fi
done <<EOF
$DESTS
EOF

for doc in AGENTS.md CLAUDE.md; do
  path="$HOST/$doc"
  [ -f "$path" ] || continue
  grep -qF "$AO_BLOCK_BEGIN" "$path" || continue
  if [ "$DRY_RUN" -eq 1 ]; then
    would "strip managed block from $doc"
  else
    ao_remove_managed_block "$path"
    ok "$doc: managed block removed"
    # Remove the file entirely if it only ever held our block.
    [ -s "$path" ] || { rm -f "$path"; skip "$doc was empty — removed"; }
  fi
done

info "done — $removed skill link(s) removed"
printf '\nAgent Ops itself is still a submodule. To remove it completely:\n  git submodule deinit -f <path-to-agent-ops>\n  git rm -f <path-to-agent-ops>\n' >&2
