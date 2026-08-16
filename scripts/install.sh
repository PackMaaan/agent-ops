#!/usr/bin/env bash
#
# Link every enabled module's skills into the host repository so that any
# Agent Skills-compatible harness discovers them.
#
# Idempotent: safe to re-run after `agent-ops module sync` or a submodule bump.
#
# Portability note: newline-delimited strings are used instead of bash arrays
# throughout, because macOS ships bash 3.2, where `${#arr[@]}` on an empty array
# is an unbound-variable error under `set -u`.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MODE="link"          # link | copy
DRY_RUN=0
TARGET=""
DESTS=""             # newline-delimited relative directories

usage() {
  cat <<'EOF'
agent-ops install — install module skills into the host repository.

USAGE
  agent-ops install [options]

OPTIONS
  --target DIR     Host repository root (default: auto-detected superproject)
  --harness NAME   Where to install skills. Repeatable. Default: claude
                     claude    -> <host>/.claude/skills
                     agents    -> <host>/.agents/skills
                     factory   -> <host>/.factory/skills
                     opencode  -> <host>/.opencode/skills
                     all       -> every directory above
  --dest DIR       Explicit skills directory, relative to the host (repeatable)
  --copy           Copy skill directories instead of symlinking them
  --dry-run        Print what would change and exit
  -h, --help       Show this message

NOTES
  Symlinks are the default: module skills stay owned by their submodule, so a
  `git submodule update` is immediately live with no reinstall. Use --copy on
  filesystems without symlink support, or when vendoring for an air-gapped CI.
  See NOTICE.md — copying carries the upstream license obligations with it.
EOF
}

add_dest() { DESTS="${DESTS}$1"$'\n'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    --harness)
      case "${2:?--harness needs a name}" in
        claude)   add_dest ".claude/skills" ;;
        agents)   add_dest ".agents/skills" ;;
        factory)  add_dest ".factory/skills" ;;
        opencode) add_dest ".opencode/skills" ;;
        all)      add_dest ".claude/skills"; add_dest ".agents/skills"
                  add_dest ".factory/skills"; add_dest ".opencode/skills" ;;
        *) die "unknown harness: $2 (try: claude, agents, factory, opencode, all)" ;;
      esac
      shift 2 ;;
    --dest) add_dest "${2:?--dest needs a directory}"; shift 2 ;;
    --copy) MODE="copy"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[ -n "$DESTS" ] || add_dest ".claude/skills"

[ -n "$TARGET" ] && AGENT_OPS_HOST="$TARGET"
export AGENT_OPS_HOST="${AGENT_OPS_HOST:-}"
HOST=$(ao_require_host_root)

info "Agent Ops $AGENT_OPS_VERSION"
info "host repository: $HOST"
[ "$DRY_RUN" -eq 1 ] && warn "dry run — no changes will be written"

# --- 1. Make sure the submodules are actually checked out -------------------

missing=0
while IFS=$'\t' read -r id kind path _name; do
  [ "$kind" = "submodule" ] || continue
  if [ ! -e "$AO_ROOT/$path/.git" ]; then
    warn "module '$id' is not checked out at $path"
    missing=1
  fi
done < <(ao_modules)

if [ "$missing" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    would "run: git -C '$AO_ROOT' submodule update --init --recursive"
  else
    info "initialising submodules"
    git -C "$AO_ROOT" submodule update --init --recursive
  fi
fi

# --- 2. Link (or copy) each skill into each destination ---------------------

installed=""   # newline-delimited skill names, deduplicated across destinations

while IFS= read -r dest_rel; do
  [ -n "$dest_rel" ] || continue
  dest="$HOST/$dest_rel"
  info "installing into ${dest_rel}/"

  if [ ! -d "$dest" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then would "create $dest_rel/"; else mkdir -p "$dest"; fi
  fi

  while IFS=$'\t' read -r module_id skill_name source; do
    link="$dest/$skill_name"

    if [ ! -d "$source" ]; then
      fail "$skill_name: source directory missing ($source)"
      die "module '$module_id' is registered but its skill source is absent.
  Run: git -C '$AO_ROOT' submodule update --init --recursive"
    fi
    if [ ! -f "$source/SKILL.md" ]; then
      fail "$skill_name: $source has no SKILL.md"
      die "module '$module_id' does not look like an Agent Skill. Check registry/modules.json."
    fi

    case $'\n'"$installed" in
      *$'\n'"$skill_name"$'\n'*) ;;
      *) installed="${installed}${skill_name}"$'\n' ;;
    esac

    if [ "$MODE" = "copy" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        would "copy $skill_name <- $module_id"
        continue
      fi
      rm -rf "$link"
      cp -R "$source" "$link"
      ok "$skill_name (copied from $module_id)"
      continue
    fi

    if ao_link_matches "$link" "$source"; then
      skip "$skill_name (already linked)"
      continue
    fi
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      die "$link exists and is not a symlink. Move it aside, or re-run with --copy."
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      would "link $skill_name -> $(ao_relpath "$source" "$dest")"
      continue
    fi
    rm -f "$link"
    ln -s "$(ao_relpath "$source" "$dest")" "$link"
    ok "$skill_name -> $module_id"
  done < <(ao_skills)
done <<EOF
$DESTS
EOF

# --- 3. Advertise the skills in the host's agent instruction files -----------

AO_REL=$(ao_relpath "$AO_ROOT" "$HOST")

# shellcheck disable=SC2016  # backticks here are markdown code spans, not substitutions
render_block() {
  printf '## Agent Ops modules\n\n'
  printf 'Installed from [`%s/`](%s). Do not edit inside the markers — run `%s/bin/agent-ops install` instead.\n\n' \
    "$AO_REL" "$AO_REL" "$AO_REL"
  printf '| Skill | Module | Use it for |\n|---|---|---|\n'
  while IFS=$'\t' read -r module_id skill_name _source; do
    name=$(ao_module_field "$module_id" name)
    summary=$(ao_module_field "$module_id" summary)
    printf '| `%s` | %s | %s |\n' "$skill_name" "${name:-$module_id}" "${summary:-—}"
  done < <(ao_skills)
  printf '\nAfter pulling changes: `git submodule update --init --recursive && %s/bin/agent-ops install`\n' "$AO_REL"
}

for doc in AGENTS.md CLAUDE.md; do
  path="$HOST/$doc"
  if [ "$DRY_RUN" -eq 1 ]; then
    would "update managed block in $doc"
    continue
  fi
  render_block | ao_write_managed_block "$path"
  ok "$doc updated"
done

# --- 4. Keep the generated links out of `git status` ------------------------

exclude="$HOST/.git/info/exclude"
if [ "$DRY_RUN" -eq 0 ] && [ "$MODE" = "link" ] && [ -d "$HOST/.git" ]; then
  mkdir -p "$HOST/.git/info"
  touch "$exclude"
  while IFS= read -r dest_rel; do
    [ -n "$dest_rel" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      entry="$dest_rel/$name"
      grep -qxF "$entry" "$exclude" 2>/dev/null || printf '%s\n' "$entry" >>"$exclude"
    done <<EOF
$installed
EOF
  done <<EOF
$DESTS
EOF
  skip "generated symlinks excluded via .git/info/exclude"
fi

count=$(printf '%s' "$installed" | grep -c . || true)
info "done — $count skill(s) available to the host repository"
printf '\nNext:\n  %s/bin/agent-ops doctor        # verify\n  %s/bin/agent-ops bootstrap     # apply GitHub standards to this repo\n' \
  "$AO_REL" "$AO_REL" >&2
