#!/usr/bin/env bash
# Agent Ops shared shell library.
#
# Sourced by every script in scripts/ and by bin/agent-ops. Callers are expected
# to have already set `set -euo pipefail`; this file sets it too so that sourcing
# it directly in a debug shell behaves the same way.
#
# shellcheck shell=bash

set -euo pipefail

# Consumed by every sourcing script, so shellcheck cannot see the use from here.
# shellcheck disable=SC2034
readonly AGENT_OPS_VERSION="0.2.0"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Root of the Agent Ops checkout, resolved through symlinks so that a script
# invoked via a symlinked entry point still finds its own repository.
_ao_resolve_root() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir=$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)
    src=$(readlink "$src")
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  # This file lives at <root>/scripts/lib/common.sh
  cd -P "$(dirname "$src")/../.." >/dev/null 2>&1 && pwd
}

AO_ROOT="${AO_ROOT:-$(_ao_resolve_root)}"
readonly AO_ROOT

AO_REGISTRY="${AO_REGISTRY:-$AO_ROOT/registry/modules.json}"
# shellcheck disable=SC2034  # used by bootstrap-repo.sh
AO_TEMPLATES="$AO_ROOT/templates"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# shellcheck disable=SC2034  # the palette is consumed by sourcing scripts
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

info()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok()    { printf '%s  ✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
skip()  { printf '%s  ·%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }
warn()  { printf '%s  !%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Emitted instead of acting when --dry-run is in effect.
would() { printf '%s  ~%s would %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  local cmd="$1" hint="${2:-}"
  have "$cmd" && return 0
  if [ -n "$hint" ]; then
    die "'$cmd' is required but not installed. $hint"
  fi
  die "'$cmd' is required but not installed."
}

require_jq() {
  require_cmd jq "Install it with 'brew install jq' or 'apt-get install jq'."
}

# ---------------------------------------------------------------------------
# Git context
# ---------------------------------------------------------------------------

# Print the working tree root of the repository that *contains* Agent Ops.
#
# Three supported layouts, in priority order:
#   1. AGENT_OPS_HOST is set explicitly (installer --target, tests, CI).
#   2. Agent Ops is a git submodule -> the superproject working tree.
#   3. Agent Ops was cloned next to / inside a repo -> nearest enclosing repo
#      that is not Agent Ops itself.
#
# Returns non-zero and prints nothing when no host repository can be determined.
ao_host_root() {
  if [ -n "${AGENT_OPS_HOST:-}" ]; then
    [ -d "$AGENT_OPS_HOST" ] || die "AGENT_OPS_HOST is not a directory: $AGENT_OPS_HOST"
    (cd "$AGENT_OPS_HOST" && pwd)
    return 0
  fi

  local super
  super=$(git -C "$AO_ROOT" rev-parse --show-superproject-working-tree 2>/dev/null || true)
  if [ -n "$super" ]; then
    printf '%s\n' "$super"
    return 0
  fi

  # Not a submodule. Walk up from the parent directory looking for a repo that
  # is not this one.
  local parent top
  parent=$(cd "$AO_ROOT/.." >/dev/null 2>&1 && pwd) || return 1
  top=$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ] && [ "$top" != "$AO_ROOT" ]; then
    printf '%s\n' "$top"
    return 0
  fi

  return 1
}

# Same as ao_host_root but fails loudly with actionable guidance.
ao_require_host_root() {
  local host
  if ! host=$(ao_host_root); then
    die "could not determine the host repository.
  Agent Ops is designed to live inside another repository, typically as a submodule:

    git submodule add https://github.com/PackMaaan/agent-ops .agent-ops

  If you are working on Agent Ops itself, point at a target explicitly:

    AGENT_OPS_HOST=/path/to/host-repo $0 ...
    # or
    $0 --target /path/to/host-repo"
  fi
  printf '%s\n' "$host"
}

# owner/repo for the host repository, from its 'origin' remote. Empty if none.
ao_host_slug() {
  local host="$1" url
  url=$(git -C "$host" remote get-url origin 2>/dev/null || true)
  [ -n "$url" ] || return 1
  # git@github.com:owner/repo.git | https://github.com/owner/repo(.git)
  url=${url%.git}
  url=${url##*github.com[:/]}
  case "$url" in
    */*) printf '%s\n' "$url" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

ao_registry_file() {
  # A local overlay lets a host repo disable modules without editing tracked files.
  if [ -f "$AO_ROOT/registry/modules.local.json" ]; then
    printf '%s\n' "$AO_ROOT/registry/modules.local.json"
  else
    printf '%s\n' "$AO_REGISTRY"
  fi
}

ao_registry_check() {
  require_jq
  local f; f=$(ao_registry_file)
  [ -f "$f" ] || die "module registry not found: $f"
  jq -e . "$f" >/dev/null 2>&1 || die "module registry is not valid JSON: $f"
}

# Emit one TSV row per enabled module: id \t kind \t path \t name
ao_modules() {
  ao_registry_check
  jq -r '.modules[] | select(.enabled) | [.id, .kind, .path, .name] | @tsv' "$(ao_registry_file)"
}

# Emit one TSV row per skill of every enabled module:
#   module_id \t skill_name \t absolute_source_path
ao_skills() {
  ao_registry_check
  local root="$AO_ROOT"
  jq -r --arg root "$root" '
    .modules[]
    | select(.enabled)
    | . as $m
    | .skills[]
    | [ $m.id,
        .name,
        ($root + "/" + (if $m.path == "." then "" else $m.path + "/" end) + .source)
      ]
    | @tsv
  ' "$(ao_registry_file)"
}

# Look up a single field of a module by id.
ao_module_field() {
  local id="$1" field="$2"
  ao_registry_check
  jq -r --arg id "$id" --arg f "$field" '
    (.modules[] | select(.id == $id) | .[$f]) // empty
  ' "$(ao_registry_file)"
}

ao_module_exists() {
  local id="$1"
  [ -n "$(ao_module_field "$id" id)" ]
}

# ---------------------------------------------------------------------------
# Managed blocks in host-owned files
# ---------------------------------------------------------------------------

AO_BLOCK_BEGIN="<!-- BEGIN agent-ops (managed) -->"
AO_BLOCK_END="<!-- END agent-ops (managed) -->"

# Replace (or append) the managed block in $1 with the content on stdin.
# Everything outside the markers is preserved byte for byte.
#
# The body goes through a file rather than `awk -v body="$body"`: BSD awk (which
# is what macOS ships) rejects a newline inside a -v assignment with "newline in
# string" and aborts. Only the single-line markers are passed as variables.
ao_write_managed_block() {
  local file="$1" tmp body_file
  body_file="${file}.agent-ops.body"
  tmp="${file}.agent-ops.tmp"
  cat >"$body_file"

  if [ -f "$file" ] && grep -qF "$AO_BLOCK_BEGIN" "$file"; then
    {
      awk -v begin="$AO_BLOCK_BEGIN" 'index($0, begin) { exit } { print }' "$file"
      printf '%s\n' "$AO_BLOCK_BEGIN"
      cat "$body_file"
      printf '%s\n' "$AO_BLOCK_END"
      awk -v end="$AO_BLOCK_END" 'seen { print } index($0, end) { seen = 1 }' "$file"
    } >"$tmp"
  else
    {
      if [ -f "$file" ] && [ -s "$file" ]; then
        cat "$file"
        printf '\n'
      fi
      printf '%s\n' "$AO_BLOCK_BEGIN"
      cat "$body_file"
      printf '%s\n' "$AO_BLOCK_END"
    } >"$tmp"
  fi

  rm -f "$body_file"
  mv "$tmp" "$file"
}

# Remove the managed block from $1, leaving the rest of the file intact.
ao_remove_managed_block() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  grep -qF "$AO_BLOCK_BEGIN" "$file" || return 0
  tmp="${file}.agent-ops.tmp"
  awk -v begin="$AO_BLOCK_BEGIN" -v end="$AO_BLOCK_END" '
    index($0, begin) { skipping = 1; next }
    index($0, end)   { skipping = 0; next }
    !skipping        { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

# Portable `realpath --relative-to`, implemented in pure shell because macOS
# ships neither GNU realpath nor `readlink -f`.
#
# Falls back to the absolute path when the two arguments share no ancestor
# below '/'. That is the normal case only when Agent Ops was installed with
# --target across unrelated trees; in the intended submodule layout the host
# always contains the Agent Ops checkout, so the result is relative and the
# generated symlinks survive the repository being moved or re-cloned.
ao_relpath() {
  local target="$1" base="$2" common up=""
  target=${target%/}; base=${base%/}
  common="$base"
  while [ "${target#"$common"/}" = "$target" ] && [ "$common" != "/" ] && [ -n "$common" ]; do
    common=$(dirname "$common")
    up="../$up"
  done
  if [ "$common" = "/" ]; then
    printf '%s\n' "$target"
  else
    printf '%s\n' "${up}${target#"$common"/}"
  fi
}

# True when $1 is a symlink already pointing at $2 (compared after resolution).
ao_link_matches() {
  local link="$1" want="$2" have_target
  [ -L "$link" ] || return 1
  have_target=$(cd "$(dirname "$link")" >/dev/null 2>&1 && cd -P "$(readlink "$link")" >/dev/null 2>&1 && pwd) || return 1
  [ "$have_target" = "$(cd -P "$want" >/dev/null 2>&1 && pwd)" ]
}
