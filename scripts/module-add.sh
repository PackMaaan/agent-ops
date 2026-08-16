#!/usr/bin/env bash
#
# Register a new capability module: add the git submodule and write the
# registry entry in one rollback-protected step, then verify the result.
#
# This is the supported way to grow Agent Ops. Hand-editing .gitmodules and
# registry/modules.json separately is what CI's registry check exists to catch.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ID=""
URL=""
BRANCH="main"
MOD_PATH=""
NAME=""
SUMMARY=""
LICENSE=""
UPSTREAM=""
SKILLS=""     # newline-delimited NAME=SRC pairs
CAPS=""       # newline-delimited capability tags
DRY_RUN=0

usage() {
  cat <<'EOF'
agent-ops module add — register a new capability module as a git submodule.

USAGE
  agent-ops module add --id ID --url GIT_URL [options]

REQUIRED
  --id ID           Registry identifier (lowercase, dash-separated)
  --url GIT_URL     Clone URL for the module repository

OPTIONS
  --branch NAME     Branch to track (default: main)
  --path DIR        Checkout path (default: modules/<id>)
  --name TEXT       Human-readable name (default: derived from --id)
  --summary TEXT    One-line description shown in `module list` and AGENTS.md
  --license TEXT    SPDX expression, recorded for NOTICE.md
  --upstream URL    Canonical origin, when --url points at a fork
  --skill NAME=SRC  Skill to expose, SRC relative to the module root.
                    Repeatable. Auto-detected from the checkout when omitted.
  --capability CAP  Capability tag. Repeatable.
  --dry-run         Show what would happen without touching anything
  -h, --help        Show this message

EXAMPLE
  agent-ops module add \
    --id security-audit \
    --url https://github.com/acme/security-audit-skill.git \
    --summary "OWASP and CVE review workflows" \
    --license MIT \
    --skill security-audit=skills/security-audit \
    --capability security --capability review
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --id) ID="${2:?--id needs a value}"; shift 2 ;;
    --url) URL="${2:?--url needs a value}"; shift 2 ;;
    --branch) BRANCH="${2:?--branch needs a value}"; shift 2 ;;
    --path) MOD_PATH="${2:?--path needs a value}"; shift 2 ;;
    --name) NAME="${2:?--name needs a value}"; shift 2 ;;
    --summary) SUMMARY="${2:?--summary needs a value}"; shift 2 ;;
    --license) LICENSE="${2:?--license needs a value}"; shift 2 ;;
    --upstream) UPSTREAM="${2:?--upstream needs a value}"; shift 2 ;;
    --skill) SKILLS="${SKILLS}${2:?--skill needs NAME=SRC}"$'\n'; shift 2 ;;
    --capability) CAPS="${CAPS}${2:?--capability needs a value}"$'\n'; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[ -n "$ID" ] || { usage >&2; die "--id is required"; }
[ -n "$URL" ] || { usage >&2; die "--url is required"; }
printf '%s' "$ID" | grep -Eq '^[a-z0-9][a-z0-9-]*$' \
  || die "--id must match ^[a-z0-9][a-z0-9-]*\$ — got: $ID"

require_jq
require_cmd git
ao_registry_check

[ -n "$MOD_PATH" ] || MOD_PATH="modules/$ID"
[ -n "$NAME" ] || NAME=$(printf '%s' "$ID" | tr '-' ' ')

ao_module_exists "$ID" && die "module '$ID' is already registered. Run 'agent-ops module remove $ID' first."
[ -e "$AO_ROOT/$MOD_PATH" ] && die "path already exists: $MOD_PATH"

info "adding module '$ID'"
printf '  url      %s\n  branch   %s\n  path     %s\n' "$URL" "$BRANCH" "$MOD_PATH" >&2

if [ "$DRY_RUN" -eq 1 ]; then
  would "git submodule add --branch $BRANCH $URL $MOD_PATH"
  would "add registry entry for '$ID'"
  exit 0
fi

# --- 1. Add the submodule ---------------------------------------------------

git -C "$AO_ROOT" submodule add --branch "$BRANCH" "$URL" "$MOD_PATH"
git -C "$AO_ROOT" config -f .gitmodules "submodule.$MOD_PATH.shallow" false
ok "submodule checked out at $MOD_PATH"

rollback() {
  warn "rolling back submodule '$MOD_PATH'"
  git -C "$AO_ROOT" submodule deinit -f "$MOD_PATH" >/dev/null 2>&1 || true
  git -C "$AO_ROOT" rm -f "$MOD_PATH" >/dev/null 2>&1 || true
  rm -rf "${AO_ROOT:?}/.git/modules/$MOD_PATH"
}
trap rollback ERR

# --- 2. Work out which skills the module exposes ----------------------------

if [ -z "$SKILLS" ]; then
  info "auto-detecting skills"
  while IFS= read -r skill_md; do
    [ -n "$skill_md" ] || continue
    rel=${skill_md#"$AO_ROOT/$MOD_PATH/"}
    rel=$(dirname "$rel")
    SKILLS="${SKILLS}$(basename "$rel")=$rel"$'\n'
    ok "found $rel"
  done < <(find "$AO_ROOT/$MOD_PATH" -maxdepth 4 -name SKILL.md -not -path '*/.git/*' 2>/dev/null | sort)
  [ -n "$SKILLS" ] || die "no SKILL.md found under $MOD_PATH — pass --skill NAME=SRC explicitly"
fi

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  skill_name=${entry%%=*}
  skill_src=${entry#*=}
  [ "$skill_name" != "$entry" ] || die "--skill must be NAME=SRC, got: $entry"
  [ -f "$AO_ROOT/$MOD_PATH/$skill_src/SKILL.md" ] || die "no SKILL.md at $MOD_PATH/$skill_src"
  ao_registry_check
  if jq -e --arg n "$skill_name" '.modules[].skills[] | select(.name == $n)' "$AO_REGISTRY" >/dev/null 2>&1; then
    die "skill name '$skill_name' is already used by another module — names must be unique"
  fi
done <<EOF
$SKILLS
EOF

# --- 3. Write the registry entry -------------------------------------------

skills_json=$(printf '%s' "$SKILLS" | grep . | jq -R 'split("=") | {name: .[0], source: .[1]}' | jq -s '.')
caps_json='[]'
[ -n "$CAPS" ] && caps_json=$(printf '%s' "$CAPS" | grep . | jq -R . | jq -s '.')

tmp="$AO_REGISTRY.tmp"
jq --arg id "$ID" \
   --arg name "$NAME" \
   --arg summary "$SUMMARY" \
   --arg path "$MOD_PATH" \
   --arg url "$URL" \
   --arg branch "$BRANCH" \
   --arg upstream "$UPSTREAM" \
   --arg license "$LICENSE" \
   --argjson skills "$skills_json" \
   --argjson caps "$caps_json" '
  .modules += [
    ({
      id: $id,
      name: $name,
      kind: "submodule",
      path: $path,
      url: $url,
      branch: $branch,
      enabled: true,
      skills: $skills
    }
    + (if $summary  != "" then {summary: $summary}   else {} end)
    + (if $upstream != "" then {upstream: $upstream} else {} end)
    + (if $license  != "" then {license: $license}   else {} end)
    + (if ($caps | length) > 0 then {capabilities: $caps} else {} end))
  ]
  | .modules |= (map(select(.kind == "builtin")) + (map(select(.kind != "builtin")) | sort_by(.id)))
' "$AO_REGISTRY" >"$tmp"

mv "$tmp" "$AO_REGISTRY"
ok "registry entry added"

trap - ERR

# --- 4. Verify --------------------------------------------------------------

if "$AO_ROOT/scripts/doctor.sh" >/dev/null 2>&1; then
  ok "doctor passes"
else
  warn "doctor reported issues — run 'agent-ops doctor'"
fi

info "module '$ID' registered"
cat >&2 <<EOF

Next:
  1. Review the diff:      git -C "$AO_ROOT" diff
  2. Record the license:   edit NOTICE.md
  3. Install the skills:   agent-ops install
  4. Commit:               git add .gitmodules $MOD_PATH registry/modules.json NOTICE.md
                           git commit -m "feat(modules): add $ID"
EOF
