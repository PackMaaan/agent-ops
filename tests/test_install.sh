#!/usr/bin/env bash
#
# Install / uninstall against a throwaway host repository.
#
# The bulk of the suite drives the scripts with --target so that the *working
# tree* is what gets tested, not the last commit. One dedicated test covers
# superproject auto-detection by adding Agent Ops as a real submodule; that one
# necessarily exercises committed state and skips itself on a repo with no HEAD.

set -uo pipefail
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

printf 'install / uninstall\n'

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t agent-ops-test)
trap 'rm -rf "$WORK"' EXIT

AO="$ROOT/bin/agent-ops"
HOST="$WORK/host"
make_host_repo "$HOST"

it "modules are checked out"
assert_file "$ROOT/modules/ccpm/skill/ccpm/SKILL.md"

it "github-project module is checked out"
assert_file "$ROOT/modules/github-project/skills/github-project/SKILL.md"

# --- dry run must not touch anything ---------------------------------------

it "--dry-run writes nothing"
"$AO" install --target "$HOST" --dry-run >/dev/null 2>&1
assert_no_file "$HOST/.claude/skills"

# --- install ---------------------------------------------------------------

"$AO" install --target "$HOST" >/dev/null 2>&1
INSTALL_RC=$?

it "install exits zero"
assert_eq "$INSTALL_RC" "0"

it "ccpm skill is linked"
assert_symlink "$HOST/.claude/skills/ccpm"

it "github-project skill is linked"
assert_symlink "$HOST/.claude/skills/github-project"

it "agent-ops meta-skill is linked"
assert_symlink "$HOST/.claude/skills/agent-ops"

it "linked ccpm skill resolves to a real SKILL.md"
assert_file "$HOST/.claude/skills/ccpm/SKILL.md"

it "linked github-project skill resolves to a real SKILL.md"
assert_file "$HOST/.claude/skills/github-project/SKILL.md"

it "linked agent-ops skill resolves to a real SKILL.md"
assert_file "$HOST/.claude/skills/agent-ops/SKILL.md"

it "AGENTS.md managed block was written"
assert_contains "$HOST/AGENTS.md" "BEGIN agent-ops (managed)"

it "CLAUDE.md managed block was closed"
assert_contains "$HOST/CLAUDE.md" "END agent-ops (managed)"

it "managed block lists every installed skill"
# shellcheck disable=SC2016  # backticks are markdown code spans in the rendered table
assert_contains "$HOST/AGENTS.md" '`github-project`'

it "generated links are excluded from git status"
assert_contains "$HOST/.git/info/exclude" ".claude/skills/ccpm"

it "host working tree shows no untracked skill links"
status=$(git -C "$HOST" status --porcelain | grep -c '.claude/skills' || true)
assert_eq "$status" "0"

# --- idempotence ------------------------------------------------------------

it "second install leaves the link unchanged"
before=$(readlink "$HOST/.claude/skills/ccpm")
"$AO" install --target "$HOST" >/dev/null 2>&1
after=$(readlink "$HOST/.claude/skills/ccpm")
assert_eq "$after" "$before"

it "second install does not duplicate the managed block"
count=$(grep -c "BEGIN agent-ops (managed)" "$HOST/AGENTS.md")
assert_eq "$count" "1"

it "second install does not duplicate the exclude entry"
count=$(grep -cxF ".claude/skills/ccpm" "$HOST/.git/info/exclude")
assert_eq "$count" "1"

# --- pre-existing host content must survive ---------------------------------

it "host-authored content around the managed block is preserved"
{ printf 'Host-authored line.\n'; cat "$HOST/AGENTS.md"; } >"$HOST/AGENTS.tmp"
mv "$HOST/AGENTS.tmp" "$HOST/AGENTS.md"
"$AO" install --target "$HOST" >/dev/null 2>&1
assert_contains "$HOST/AGENTS.md" "Host-authored line."

it "the managed block is still intact after a rewrite"
# shellcheck disable=SC2016  # backticks are markdown code spans
assert_contains "$HOST/AGENTS.md" '`ccpm`'

# --- alternate destinations -------------------------------------------------

it "--harness factory installs to .factory/skills"
"$AO" install --target "$HOST" --harness factory >/dev/null 2>&1
assert_symlink "$HOST/.factory/skills/ccpm"

it "--dest --copy produces real directories, not links"
"$AO" install --target "$HOST" --dest .vendored/skills --copy >/dev/null 2>&1
if [ -d "$HOST/.vendored/skills/ccpm" ] && [ ! -L "$HOST/.vendored/skills/ccpm" ]; then
  pass
else
  failed "expected a real directory at .vendored/skills/ccpm"
fi

it "copied skill contains the real content"
assert_file "$HOST/.vendored/skills/ccpm/SKILL.md"

# --- refusal cases ----------------------------------------------------------

it "refuses to clobber a real directory where a link belongs"
HOST_X="$WORK/host-x"
make_host_repo "$HOST_X"
mkdir -p "$HOST_X/.claude/skills/ccpm"
printf 'mine\n' >"$HOST_X/.claude/skills/ccpm/SKILL.md"
assert_fails "$AO" install --target "$HOST_X"

it "the pre-existing directory survived the refusal"
assert_contains "$HOST_X/.claude/skills/ccpm/SKILL.md" "mine"

# --- doctor -----------------------------------------------------------------

it "doctor passes on a healthy install"
assert_ok "$AO" doctor --target "$HOST"

it "module list runs"
assert_ok "$AO" module list

it "version prints"
assert_ok "$AO" version

it "unknown command fails"
assert_fails "$AO" definitely-not-a-command

# --- uninstall --------------------------------------------------------------

"$AO" uninstall --target "$HOST" --dest .vendored/skills --purge >/dev/null 2>&1

it "uninstall removes the ccpm link"
assert_no_file "$HOST/.claude/skills/ccpm"

it "uninstall removes the factory link"
assert_no_file "$HOST/.factory/skills/ccpm"

it "uninstall --purge removes copied directories"
assert_no_file "$HOST/.vendored/skills/ccpm"

it "uninstall strips the managed block"
assert_not_contains "$HOST/AGENTS.md" "BEGIN agent-ops (managed)"

it "uninstall preserves host-authored content"
assert_contains "$HOST/AGENTS.md" "Host-authored line."

it "host README is untouched"
assert_contains "$HOST/README.md" "Pre-existing content that must survive."

# --- superproject auto-detection (committed state) --------------------------

printf '\n  superproject detection\n'
if ! git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  printf '  %s·%s skipped — Agent Ops has no commits yet\n' "$T_DIM" "$T_RESET"
else
  SUB_HOST="$WORK/sub-host"
  make_host_repo "$SUB_HOST"
  if git -c protocol.file.allow=always -C "$SUB_HOST" submodule add -q "$ROOT" .agent-ops >/dev/null 2>&1; then
    # Re-point the inner submodules at the local checkouts so the test stays offline.
    for m in modules/ccpm modules/github-project; do
      git -C "$SUB_HOST/.agent-ops" config "submodule.$m.url" "$ROOT/$m"
    done
    git -c protocol.file.allow=always -C "$SUB_HOST/.agent-ops" \
      submodule update --init --recursive >/dev/null 2>&1

    it "install auto-detects the superproject with no --target"
    "$SUB_HOST/.agent-ops/bin/agent-ops" install >/dev/null 2>&1
    assert_symlink "$SUB_HOST/.claude/skills/ccpm"

    it "the auto-detected link resolves"
    assert_file "$SUB_HOST/.claude/skills/ccpm/SKILL.md"

    # Only meaningful in this layout: the host contains the Agent Ops checkout,
    # so the link must be relative or it breaks on every other clone.
    it "the symlink is relative, not absolute"
    target=$(readlink "$SUB_HOST/.claude/skills/ccpm")
    case "$target" in /*) failed "symlink is absolute: $target" ;; *) pass ;; esac

    it "AGENTS.md was written into the superproject, not the submodule"
    assert_file "$SUB_HOST/AGENTS.md"

    # Agent Ops ships its own AGENTS.md, so "did install target the
    # superproject and not itself?" is answered by the submodule working tree
    # still being pristine — not by grepping for a marker the file documents.
    it "the submodule working tree is untouched by install"
    dirty=$(git -C "$SUB_HOST/.agent-ops" status --porcelain | grep -c . || true)
    assert_eq "$dirty" "0"
  else
    printf '  %s·%s skipped — could not add the local submodule\n' "$T_DIM" "$T_RESET"
  fi
fi

summary
