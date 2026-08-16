#!/usr/bin/env bash
#
# Bootstrap's file phase, exercised offline. Nothing here touches the GitHub
# API — the remote phase is disabled throughout.

set -uo pipefail
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

printf 'bootstrap (files phase, offline)\n'

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t agent-ops-boot)
trap 'rm -rf "$WORK"' EXIT

HOST="$WORK/host"
make_host_repo "$HOST"
git -C "$HOST" remote add origin https://github.com/acme/widget.git

BOOT=("$ROOT/scripts/bootstrap-repo.sh" --target "$HOST" --no-remote --no-labels)

it "--dry-run writes nothing"
"${BOOT[@]}" --dry-run >/dev/null 2>&1
assert_no_file "$HOST/SECURITY.md"

"${BOOT[@]}" >/dev/null 2>&1
RC=$?

it "bootstrap exits zero"
assert_eq "$RC" "0"

it "SECURITY.md is created"
assert_file "$HOST/SECURITY.md"

it "CONTRIBUTING.md is created"
assert_file "$HOST/CONTRIBUTING.md"

it "CODE_OF_CONDUCT.md is created"
assert_file "$HOST/CODE_OF_CONDUCT.md"

it "CODEOWNERS is created"
assert_file "$HOST/.github/CODEOWNERS"

it "PR template is created"
assert_file "$HOST/.github/PULL_REQUEST_TEMPLATE.md"

it "bug report issue form is created"
assert_file "$HOST/.github/ISSUE_TEMPLATE/bug_report.yml"

it "feature request issue form is created"
assert_file "$HOST/.github/ISSUE_TEMPLATE/feature_request.yml"

it "issue template config is created"
assert_file "$HOST/.github/ISSUE_TEMPLATE/config.yml"

it "release notes config is created"
assert_file "$HOST/.github/release.yml"

it "dependabot config is generated"
assert_file "$HOST/.github/dependabot.yml"

it ".editorconfig is created"
assert_file "$HOST/.editorconfig"

it ".gitattributes is created"
assert_file "$HOST/.gitattributes"

# --- substitution -----------------------------------------------------------

it "ORG placeholder is substituted"
assert_contains "$HOST/.github/CODEOWNERS" "@acme"

it "SLUG placeholder is substituted in the issue template config"
assert_contains "$HOST/.github/ISSUE_TEMPLATE/config.yml" "acme/widget"

it "no unresolved placeholders remain in the issue template config"
assert_not_contains "$HOST/.github/ISSUE_TEMPLATE/config.yml" "{{"

it "dependabot detected the github-actions ecosystem"
assert_contains "$HOST/.github/dependabot.yml" "github-actions"

it "generated dependabot config is valid YAML shape"
assert_contains "$HOST/.github/dependabot.yml" "version: 2"

# --- ecosystem detection ----------------------------------------------------

it "npm projects get an npm dependabot block"
HOST2="$WORK/host2"
make_host_repo "$HOST2"
printf '{"name":"x","version":"1.0.0"}\n' >"$HOST2/package.json"
"$ROOT/scripts/bootstrap-repo.sh" --target "$HOST2" --no-remote --no-labels >/dev/null 2>&1
assert_contains "$HOST2/.github/dependabot.yml" 'package-ecosystem: "npm"'

# --- idempotence and --force ------------------------------------------------

it "existing files are not overwritten"
printf 'CUSTOM SECURITY POLICY\n' >"$HOST/SECURITY.md"
"${BOOT[@]}" >/dev/null 2>&1
assert_contains "$HOST/SECURITY.md" "CUSTOM SECURITY POLICY"

it "--force overwrites"
"${BOOT[@]}" --force >/dev/null 2>&1
assert_not_contains "$HOST/SECURITY.md" "CUSTOM SECURITY POLICY"

# --- extra variables --------------------------------------------------------

it "--var supplies a value the detector cannot know"
HOST3="$WORK/host3"
make_host_repo "$HOST3"
git -C "$HOST3" remote add origin https://github.com/acme/thing.git
"$ROOT/scripts/bootstrap-repo.sh" --target "$HOST3" --no-remote --no-labels \
  --security-email "sec@acme.test" >/dev/null 2>&1
assert_contains "$HOST3/CODE_OF_CONDUCT.md" "sec@acme.test"

# --- repos with no remote ---------------------------------------------------

it "works on a repository with no origin remote"
HOST4="$WORK/host4"
make_host_repo "$HOST4"
"$ROOT/scripts/bootstrap-repo.sh" --target "$HOST4" --no-remote --no-labels >/dev/null 2>&1
assert_file "$HOST4/CODE_OF_CONDUCT.md"

# --- copilot ----------------------------------------------------------------

it "copilot instructions are written by default"
assert_file "$HOST/.github/copilot-instructions.md"

it "--no-copilot skips them"
HOST5="$WORK/host5"
make_host_repo "$HOST5"
"$ROOT/scripts/bootstrap-repo.sh" --target "$HOST5" --no-remote --no-labels --no-copilot >/dev/null 2>&1
assert_no_file "$HOST5/.github/copilot-instructions.md"

# --- automation is opt-in ---------------------------------------------------

it "workflows are NOT installed without --workflows"
assert_no_file "$HOST/.github/workflows/pr-auto-update.yml"

it "the killswitch is NOT installed without --workflows"
assert_no_file "$HOST/.github/WORKFLOW_KILLSWITCH"

WF="$WORK/host-wf"
make_host_repo "$WF"
git -C "$WF" remote add origin https://github.com/acme/wf.git

it "--workflows --dry-run writes nothing"
"$ROOT/scripts/bootstrap-repo.sh" --target "$WF" --no-remote --no-labels --no-files \
  --workflows --dry-run >/dev/null 2>&1
assert_no_file "$WF/.github/workflows/pr-auto-update.yml"

"$ROOT/scripts/bootstrap-repo.sh" --target "$WF" --no-remote --no-labels --no-files \
  --workflows >/dev/null 2>&1

it "--workflows installs the killswitch"
assert_contains "$WF/.github/WORKFLOW_KILLSWITCH" "ENABLED"

for w in pr-auto-update pr-issue-auto-close pr-status-labels issue-triage coderabbit-to-issues; do
  it "--workflows installs $w.yml"
  assert_file "$WF/.github/workflows/$w.yml"
done

it "--workflows installs the coderabbit script, executable"
if [ -x "$WF/.github/scripts/coderabbit-to-issues.sh" ]; then pass; else failed "not executable"; fi

it "every installed workflow is gated by the killswitch"
missing=""
for f in "$WF"/.github/workflows/*.yml; do
  grep -q 'WORKFLOW_KILLSWITCH' "$f" || missing="$missing $(basename "$f")"
done
assert_eq "$missing" ""

it "every installed workflow declares needs: guard on its real jobs"
missing=""
for f in "$WF"/.github/workflows/*.yml; do
  grep -q 'needs: guard' "$f" || missing="$missing $(basename "$f")"
done
assert_eq "$missing" ""

it "no workflow interpolates untrusted event body into a run block"
# ${{ github.event.*.body|title }} must reach the shell through env:, never inline.
bad=""
for f in "$WF"/.github/workflows/*.yml; do
  if grep -nE '^\s+run:.*\$\{\{\s*github\.event\.[a-z_]+\.(body|title)' "$f" >/dev/null 2>&1; then
    bad="$bad $(basename "$f")"
  fi
done
assert_eq "$bad" ""

# Workflows are copied verbatim, never rendered, so they stay byte-identical to
# what CI lints. `${{ ... }}` is Actions expression syntax and must survive; an
# agent-ops `{{VAR}}` placeholder must not appear at all.
it "no agent-ops placeholder survives in an installed workflow"
found=""
for f in "$WF"/.github/workflows/*.yml; do
  grep -qE '(^|[^$])\{\{[A-Z_]+\}\}' "$f" && found="$found $(basename "$f")"
done
assert_eq "$found" ""

it "Actions expressions are preserved verbatim"
assert_contains "$WF/.github/workflows/pr-auto-update.yml" 'secrets.PR_AUTOUPDATE_TOKEN'

it "each installed workflow is byte-identical to its template"
differs=""
for f in "$WF"/.github/workflows/*.yml; do
  base=$(basename "$f")
  diff -q "$ROOT/templates/github-standards/workflows/$base" "$f" >/dev/null 2>&1 \
    || differs="$differs $base"
done
assert_eq "$differs" ""

it "--workflows does not install the stacked-delivery workflow"
assert_no_file "$WF/.github/workflows/stack-plan-suggestions.yml"

# --- stacked delivery -------------------------------------------------------

SD="$WORK/host-sd"
make_host_repo "$SD"
"$ROOT/scripts/bootstrap-repo.sh" --target "$SD" --no-remote --no-labels --no-files \
  --stacked-delivery >/dev/null 2>&1

it "--stacked-delivery installs the stack plan workflow"
assert_file "$SD/.github/workflows/stack-plan-suggestions.yml"

it "--stacked-delivery installs the stacked delivery issue form"
assert_file "$SD/.github/ISSUE_TEMPLATE/stacked_delivery_plan.yml"

for v in platform-stack-full platform-stack-minimal client-stack-full client-stack-minimal; do
  it "--stacked-delivery installs $v.md"
  assert_file "$SD/.github/PULL_REQUEST_TEMPLATE/$v.md"
done

it "--stacked-delivery installs the chooser as the root PR template"
assert_contains "$SD/.github/PULL_REQUEST_TEMPLATE.md" "?template=platform-stack-full.md"

it "an existing root PR template is not replaced without --force"
SD2="$WORK/host-sd2"
make_host_repo "$SD2"
mkdir -p "$SD2/.github"
printf 'MY OWN TEMPLATE\n' >"$SD2/.github/PULL_REQUEST_TEMPLATE.md"
"$ROOT/scripts/bootstrap-repo.sh" --target "$SD2" --no-remote --no-labels --no-files \
  --stacked-delivery >/dev/null 2>&1
assert_contains "$SD2/.github/PULL_REQUEST_TEMPLATE.md" "MY OWN TEMPLATE"

# --- guardrails -------------------------------------------------------------

GR="$WORK/host-gr"
make_host_repo "$GR"

it "--guardrails --dry-run writes nothing"
"$ROOT/scripts/bootstrap-repo.sh" --target "$GR" --no-remote --no-labels --no-files \
  --guardrails --dry-run >/dev/null 2>&1
assert_no_file "$GR/.claude/hooks/block-dangerous-git.sh"

"$ROOT/scripts/bootstrap-repo.sh" --target "$GR" --no-remote --no-labels --no-files \
  --guardrails >/dev/null 2>&1

it "--guardrails installs the hook"
assert_file "$GR/.claude/hooks/block-dangerous-git.sh"

it "the installed hook is executable"
if [ -x "$GR/.claude/hooks/block-dangerous-git.sh" ]; then pass; else failed "not executable"; fi

it "the installed hook actually blocks"
printf '{"tool_input":{"command":"git push origin main"}}' \
  | bash "$GR/.claude/hooks/block-dangerous-git.sh" >/dev/null 2>&1
assert_eq "$?" "2"

it "--guardrails registers the hook in .claude/settings.json"
assert_contains "$GR/.claude/settings.json" "block-dangerous-git.sh"

it "settings.json remains valid JSON"
assert_ok jq -e . "$GR/.claude/settings.json"

it "re-running does not register the hook twice"
"$ROOT/scripts/bootstrap-repo.sh" --target "$GR" --no-remote --no-labels --no-files \
  --guardrails >/dev/null 2>&1
count=$(jq '[.hooks.PreToolUse[]?] | length' "$GR/.claude/settings.json")
assert_eq "$count" "1"

it "pre-existing settings.json content is preserved"
GR2="$WORK/host-gr2"
make_host_repo "$GR2"
mkdir -p "$GR2/.claude"
printf '{"model":"opus","env":{"FOO":"bar"}}\n' >"$GR2/.claude/settings.json"
"$ROOT/scripts/bootstrap-repo.sh" --target "$GR2" --no-remote --no-labels --no-files \
  --guardrails >/dev/null 2>&1
assert_eq "$(jq -r .env.FOO "$GR2/.claude/settings.json")" "bar"

summary
