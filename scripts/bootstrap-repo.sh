#!/usr/bin/env bash
#
# Apply world-class GitHub standards to the host repository.
#
# Composition rule: where the `github-project` module already ships an asset
# template, that template wins. Agent Ops only supplies what the module does
# not cover (issue forms, release notes config, label taxonomy, editor config).
# We never fork upstream content just to tweak it.
#
# Three phases, each independently skippable:
#   files    — render standard files into the working tree
#   labels   — sync the label taxonomy
#   remote   — repository settings + branch protection via the GitHub API

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TARGET=""
DRY_RUN=0
FORCE=0
DO_FILES=1
DO_LABELS=1
DO_REMOTE=1
APPROVALS=1
MERGE_STRATEGY="merge"
SECURITY_EMAIL=""
EXTRA_VARS=""        # newline-delimited KEY=VALUE pairs (bash 3.2 has no safe empty arrays)

usage() {
  cat <<'EOF'
agent-ops bootstrap — apply world-class GitHub standards to the host repository.

USAGE
  agent-ops bootstrap [options]

PHASES (all on by default)
  --files-only        Only render standard files
  --labels-only       Only sync the label taxonomy
  --remote-only       Only apply repository settings + branch protection
  --no-files          Skip file rendering
  --no-labels         Skip label sync
  --no-remote         Skip every GitHub API call (offline-safe)

OPTIONS
  --target DIR              Host repository root (default: auto-detected)
  --force                   Overwrite files that already exist
  --approvals N             Required approving reviews (default: 1)
  --merge-strategy STRATEGY merge | squash | rebase (default: merge)
  --security-email ADDR     Contact address for SECURITY.md
  --var KEY=VALUE           Extra template variable. Repeatable.
  --dry-run                 Print what would change and exit
  -h, --help                Show this message

TEMPLATE VARIABLES
  Resolved automatically: ORG, REPO, PROJECT, SLUG, YEAR, DEFAULT_BRANCH,
  SECURITY_EMAIL, ECOSYSTEM. Anything still unresolved after rendering is
  reported so you can fill it in — nothing is silently left as {{PLACEHOLDER}}.

ORDER OF OPERATIONS
  Branch protection requires the default branch ref to exist. On a brand-new
  repository: commit, push, then run the remote phase.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --approvals) APPROVALS="${2:?--approvals needs a number}"; shift 2 ;;
    --merge-strategy) MERGE_STRATEGY="${2:?--merge-strategy needs a value}"; shift 2 ;;
    --security-email) SECURITY_EMAIL="${2:?--security-email needs an address}"; shift 2 ;;
    --var) EXTRA_VARS="${EXTRA_VARS}${2:?--var needs KEY=VALUE}"$'\n'; shift 2 ;;
    --files-only) DO_LABELS=0; DO_REMOTE=0; shift ;;
    --labels-only) DO_FILES=0; DO_REMOTE=0; shift ;;
    --remote-only) DO_FILES=0; DO_LABELS=0; shift ;;
    --no-files) DO_FILES=0; shift ;;
    --no-labels) DO_LABELS=0; shift ;;
    --no-remote) DO_REMOTE=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

case "$MERGE_STRATEGY" in
  merge|squash|rebase) ;;
  *) die "--merge-strategy must be one of: merge, squash, rebase" ;;
esac

[ -n "$TARGET" ] && AGENT_OPS_HOST="$TARGET"
export AGENT_OPS_HOST="${AGENT_OPS_HOST:-}"
HOST=$(ao_require_host_root)

GP_ASSETS="$AO_ROOT/modules/github-project/skills/github-project/assets"
GP_SCRIPTS="$AO_ROOT/modules/github-project/skills/github-project/scripts"
OWN="$AO_TEMPLATES/github-standards"

info "Agent Ops $AGENT_OPS_VERSION — repository bootstrap"
info "host: $HOST"
[ "$DRY_RUN" -eq 1 ] && warn "dry run — no changes will be written"

SLUG=""
if SLUG=$(ao_host_slug "$HOST" 2>/dev/null); then
  ok "origin: $SLUG"
else
  SLUG=""
  warn "no GitHub 'origin' remote detected — remote phase will be skipped"
  DO_REMOTE=0
fi

ORG="${SLUG%%/*}"
REPO="${SLUG##*/}"
[ -n "$REPO" ] || REPO=$(basename "$HOST")
[ -n "$ORG" ] || ORG="OWNER"

DEFAULT_BRANCH=$(git -C "$HOST" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "main")
[ -n "$SECURITY_EMAIL" ] || SECURITY_EMAIL=$(git -C "$HOST" config user.email 2>/dev/null || echo "security@example.com")

# --- ecosystem detection ----------------------------------------------------

# github-actions is always included: bootstrap itself is about to create
# .github/, and a workflow directory that appears later would otherwise never
# get dependency updates. Dependabot no-ops harmlessly when there are none.
detect_ecosystems() {
  local h="$1"
  printf 'github-actions\n'
  [ -f "$h/package.json" ]  && printf 'npm\n'
  [ -f "$h/go.mod" ]        && printf 'gomod\n'
  [ -f "$h/composer.json" ] && printf 'composer\n'
  [ -f "$h/Cargo.toml" ]    && printf 'cargo\n'
  { [ -f "$h/pyproject.toml" ] || [ -f "$h/requirements.txt" ]; } && printf 'pip\n'
  [ -f "$h/Gemfile" ]       && printf 'bundler\n'
  [ -f "$h/pom.xml" ]       && printf 'maven\n'
  [ -f "$h/Dockerfile" ]    && printf 'docker\n'
  return 0
}

ECOSYSTEMS=$(detect_ecosystems "$HOST" | sort -u)

# The {{ECOSYSTEM}} placeholder wants the *language* ecosystem, so github-actions
# is only the answer when nothing else was found. `grep -v` exits 1 when it
# filters everything out, which pipefail would otherwise treat as fatal.
PRIMARY_ECOSYSTEM=$(printf '%s\n' "$ECOSYSTEMS" | grep -v '^github-actions$' | head -1 || true)
[ -n "$PRIMARY_ECOSYSTEM" ] || PRIMARY_ECOSYSTEM="github-actions"

# --- template rendering -----------------------------------------------------

# Build the sed program once. The substitution uses '|' as the delimiter, so
# values are escaped for '&', '|' and backslash to survive round-tripping —
# slugs contain '/' and emails contain '@', both of which are then safe.
build_sed_program() {
  local pair k v
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    k=${pair%%=*}; v=${pair#*=}
    v=$(printf '%s' "$v" | sed -e 's/[&|\\]/\\&/g')
    printf 's|{{%s}}|%s|g\n' "$k" "$v"
  done <<EOF
ORG=$ORG
REPO=$REPO
PROJECT=$REPO
SLUG=$SLUG
YEAR=$(date +%Y)
DEFAULT_BRANCH=$DEFAULT_BRANCH
SECURITY_EMAIL=$SECURITY_EMAIL
ECOSYSTEM=$PRIMARY_ECOSYSTEM
APPROVALS=$APPROVALS
MERGE_STRATEGY=$MERGE_STRATEGY
$EXTRA_VARS
EOF
}

SED_PROGRAM=$(build_sed_program)

# render <dest-relative> <source> [<source-fallback>...]
render() {
  local dest_rel="$1"; shift
  local dest="$HOST/$dest_rel" src=""

  for candidate in "$@"; do
    [ -f "$candidate" ] && { src="$candidate"; break; }
  done
  [ -n "$src" ] || { warn "$dest_rel: no template available — skipped"; return 0; }

  if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
    skip "$dest_rel (exists)"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    would "render $dest_rel from $(ao_relpath "$src" "$AO_ROOT")"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  sed -e "$SED_PROGRAM" "$src" >"$dest"

  local unresolved
  unresolved=$(grep -oE '\{\{[A-Z_]+\}\}' "$dest" 2>/dev/null | sort -u | tr '\n' ' ' || true)
  if [ -n "$unresolved" ]; then
    warn "$dest_rel written — fill in: $unresolved"
  else
    ok "$dest_rel"
  fi
}

if [ "$DO_FILES" -eq 1 ]; then
  info "phase 1/3 — standard files"

  # Module assets first: the github-project skill owns these.
  render "SECURITY.md"                       "$GP_ASSETS/SECURITY.md.template"            "$OWN/SECURITY.md"
  render "CONTRIBUTING.md"                   "$GP_ASSETS/CONTRIBUTING.md.template"        "$OWN/CONTRIBUTING.md"
  render ".github/CODEOWNERS"                "$GP_ASSETS/CODEOWNERS.template"             "$OWN/CODEOWNERS"
  render ".github/PULL_REQUEST_TEMPLATE.md"  "$GP_ASSETS/PULL_REQUEST_TEMPLATE.md.template" "$OWN/PULL_REQUEST_TEMPLATE.md"

  # Agent Ops originals: issue forms, release notes, editor config.
  render "CODE_OF_CONDUCT.md"                     "$OWN/CODE_OF_CONDUCT.md"
  render ".github/ISSUE_TEMPLATE/bug_report.yml"      "$OWN/ISSUE_TEMPLATE/bug_report.yml"
  render ".github/ISSUE_TEMPLATE/feature_request.yml" "$OWN/ISSUE_TEMPLATE/feature_request.yml"
  render ".github/ISSUE_TEMPLATE/config.yml"          "$OWN/ISSUE_TEMPLATE/config.yml"
  render ".github/release.yml"                    "$OWN/release.yml"
  render ".editorconfig"                          "$OWN/editorconfig"
  render ".gitattributes"                         "$OWN/gitattributes"

  # Dependabot is generated rather than templated: one block per detected
  # ecosystem beats a template with a single {{ECOSYSTEM}} hole.
  dep="$HOST/.github/dependabot.yml"
  if [ -e "$dep" ] && [ "$FORCE" -eq 0 ]; then
    skip ".github/dependabot.yml (exists)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    would "generate .github/dependabot.yml for: $(printf '%s' "$ECOSYSTEMS" | tr '\n' ' ')"
  else
    mkdir -p "$HOST/.github"
    {
      printf '# Managed by agent-ops bootstrap. Detected ecosystems: %s\n' "$(printf '%s' "$ECOSYSTEMS" | tr '\n' ' ')"
      printf '# https://docs.github.com/en/code-security/dependabot/dependabot-version-updates\n'
      printf 'version: 2\nupdates:\n'
      while read -r eco; do
        [ -n "$eco" ] || continue
        printf '  - package-ecosystem: "%s"\n' "$eco"
        printf '    directory: "/"\n'
        printf '    schedule:\n      interval: "weekly"\n      day: "monday"\n'
        printf '    open-pull-requests-limit: 10\n'
        printf '    labels: ["dependencies", "automated"]\n'
        printf '    commit-message:\n      prefix: "chore(deps)"\n'
        if [ "$eco" = "github-actions" ]; then
          printf '    groups:\n      actions:\n        patterns: ["*"]\n'
        else
          printf '    groups:\n      minor-and-patch:\n        update-types: ["minor", "patch"]\n'
        fi
      done <<<"$ECOSYSTEMS"
    } >"$dep"
    ok ".github/dependabot.yml ($(printf '%s' "$ECOSYSTEMS" | tr '\n' ' '))"
  fi
fi

# --- labels -----------------------------------------------------------------

if [ "$DO_LABELS" -eq 1 ]; then
  info "phase 2/3 — label taxonomy"
  if [ -z "$SLUG" ]; then
    skip "no origin remote — labels skipped"
  elif ! have gh; then
    warn "gh not installed — labels skipped"
  elif ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated — labels skipped"
  else
    require_jq
    labels_file="$OWN/labels.json"
    if [ ! -f "$labels_file" ]; then
      warn "no label taxonomy at $labels_file"
    else
      while IFS=$'\t' read -r name color description; do
        if [ "$DRY_RUN" -eq 1 ]; then
          would "sync label '$name'"
          continue
        fi
        if gh label create "$name" --repo "$SLUG" --color "$color" --description "$description" --force >/dev/null 2>&1; then
          ok "label $name"
        else
          warn "label $name failed"
        fi
      done < <(jq -r '.[] | [.name, .color, .description] | @tsv' "$labels_file")
    fi
  fi
fi

# --- remote settings + branch protection ------------------------------------

if [ "$DO_REMOTE" -eq 1 ]; then
  info "phase 3/3 — repository settings and branch protection"

  if ! have gh; then
    warn "gh not installed — remote phase skipped"
  elif ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated — run 'gh auth login'"
  else
    # `gh repo edit` toggles booleans with --enable-X=false. There is no
    # --disable-X form; passing one aborts the whole command with "unknown flag"
    # and leaves every other setting unapplied.
    case "$MERGE_STRATEGY" in
      merge)  merge_flags=(--enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false) ;;
      squash) merge_flags=(--enable-merge-commit=false --enable-squash-merge --enable-rebase-merge=false) ;;
      rebase) merge_flags=(--enable-merge-commit=false --enable-squash-merge=false --enable-rebase-merge) ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
      would "gh repo edit $SLUG ${merge_flags[*]} --delete-branch-on-merge --enable-auto-merge"
    else
      edit_err=$(gh repo edit "$SLUG" \
          "${merge_flags[@]}" \
          --delete-branch-on-merge \
          --enable-auto-merge \
          --enable-issues 2>&1) && edit_rc=0 || edit_rc=$?
      if [ "$edit_rc" -eq 0 ]; then
        ok "repository settings applied ($MERGE_STRATEGY strategy, auto-merge on, delete-on-merge on)"
      else
        warn "gh repo edit failed — $(printf '%s' "$edit_err" | head -1)"
      fi

      if gh api "repos/$SLUG" --method PATCH -F allow_update_branch=true >/dev/null 2>&1; then
        ok "always-suggest-updating-branches enabled"
      else
        warn "could not set allow_update_branch"
      fi

      # The bracketed field names must be quoted or the shell treats them as
      # glob character classes.
      if gh api "repos/$SLUG" --method PATCH \
          -f 'security_and_analysis[secret_scanning][status]=enabled' \
          -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled' \
          >/dev/null 2>&1; then
        ok "secret scanning + push protection enabled"
      else
        skip "secret scanning unavailable (private repo without Advanced Security)"
      fi

      if gh api "repos/$SLUG/vulnerability-alerts" --method PUT >/dev/null 2>&1; then
        ok "Dependabot alerts enabled"
      else
        skip "could not enable Dependabot alerts"
      fi
    fi

    # Branch protection is delegated to the github-project module, which owns
    # the drift-detection logic and refuses to clobber deliberate admin choices.
    if [ "$DRY_RUN" -eq 1 ]; then
      would "run github-project init-branch-protection.sh $SLUG"
    elif [ -x "$GP_SCRIPTS/init-branch-protection.sh" ] || [ -f "$GP_SCRIPTS/init-branch-protection.sh" ]; then
      info "delegating branch protection to the github-project module"
      if bash "$GP_SCRIPTS/init-branch-protection.sh" "$SLUG"; then
        ok "branch protection baseline applied"
      else
        rc=$?
        case "$rc" in
          4) warn "repository has no commits yet — push first, then re-run: agent-ops bootstrap --remote-only" ;;
          1) warn "branch protection drift detected — review the diff above; the module never auto-corrects" ;;
          *) warn "init-branch-protection.sh exited $rc" ;;
        esac
      fi
    else
      warn "github-project module not checked out — run 'git submodule update --init --recursive'"
    fi
  fi
fi

# --- summary ----------------------------------------------------------------

printf '\n' >&2
info "bootstrap complete"
cat >&2 <<EOF

Next:
  1. Review and commit the generated files:
       git -C "$HOST" status
  2. Fill in any {{PLACEHOLDER}} values reported above.
  3. After the first CI run, pin required status checks:
       bash $GP_SCRIPTS/init-branch-protection.sh $SLUG --from-current-checks
  4. Verify the whole setup:
       bash $GP_SCRIPTS/verify-github-project.sh "$HOST"
EOF
