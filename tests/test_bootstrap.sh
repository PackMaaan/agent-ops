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

summary
