#!/usr/bin/env bash
#
# Update submodules to the tip of the branch each one tracks, and report the
# commit range so a human can review before committing the pointer bump.
#
# Bumping a submodule pointer is a supply-chain event: this script deliberately
# stops short of committing and prints the compare URLs instead.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ONLY=""
DRY_RUN=0

usage() {
  cat <<'EOF'
agent-ops module sync — update submodules to their tracked branch tip.

USAGE
  agent-ops module sync [ID] [--dry-run]

With no ID, every enabled submodule is updated. Nothing is committed; review
the reported ranges, then commit the pointer bump yourself.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) ONLY="$1"; shift ;;
  esac
done

require_cmd git
ao_registry_check
[ -n "$ONLY" ] && { ao_module_exists "$ONLY" || die "module '$ONLY' is not registered"; }

changed=0
summary=""

while IFS=$'\t' read -r id kind path name; do
  [ "$kind" = "submodule" ] || continue
  [ -z "$ONLY" ] || [ "$ONLY" = "$id" ] || continue

  if [ ! -e "$AO_ROOT/$path/.git" ]; then
    warn "$id: not checked out — initialising"
    [ "$DRY_RUN" -eq 1 ] && { would "git submodule update --init $path"; continue; }
    git -C "$AO_ROOT" submodule update --init "$path"
  fi

  branch=$(ao_module_field "$id" branch)
  [ -n "$branch" ] || branch="main"
  before=$(git -C "$AO_ROOT/$path" rev-parse HEAD)

  if ! git -C "$AO_ROOT/$path" diff --quiet 2>/dev/null; then
    warn "$id: working tree is dirty — skipping"
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    would "fetch and fast-forward $id to origin/$branch"
    continue
  fi

  info "$id — fetching origin/$branch"
  git -C "$AO_ROOT/$path" fetch --quiet origin "$branch"
  git -C "$AO_ROOT/$path" checkout --quiet -B "$branch" "origin/$branch"
  after=$(git -C "$AO_ROOT/$path" rev-parse HEAD)

  if [ "$before" = "$after" ]; then
    skip "$id already at $(git -C "$AO_ROOT/$path" rev-parse --short HEAD)"
    continue
  fi

  changed=$((changed + 1))
  count=$(git -C "$AO_ROOT/$path" rev-list --count "$before..$after" 2>/dev/null || echo "?")
  ok "$id: ${before:0:7} -> ${after:0:7} ($count commit(s))"

  url=$(ao_module_field "$id" url)
  url=${url%.git}
  summary+="  $name ($id)
    ${before:0:7}..${after:0:7}  $count commit(s)
    $url/compare/${before}...${after}
"
  git -C "$AO_ROOT/$path" log --oneline --no-decorate "$before..$after" 2>/dev/null | head -10 | sed 's/^/      /' >&2 || true
done < <(ao_modules)

printf '\n' >&2
if [ "$changed" -eq 0 ]; then
  info "everything already up to date"
  exit 0
fi

printf '%s%d module(s) updated%s\n\n%s\n' "$C_BOLD" "$changed" "$C_RESET" "$summary" >&2
cat >&2 <<'EOF'
Review the ranges above, then commit the pointer bump:

  agent-ops doctor
  git add modules registry/modules.json
  git commit -m "chore(modules): bump pinned module revisions"
EOF
