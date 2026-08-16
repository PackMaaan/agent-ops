#!/usr/bin/env bash
#
# The version is declared in three places that must never disagree:
#   scripts/lib/common.sh   AGENT_OPS_VERSION   (what the CLI reports)
#   .claude-plugin/plugin.json                  (what a plugin host installs)
#   CHANGELOG.md            newest heading      (what humans read)
#
# CI runs this on every push; the release workflow runs it with --expect to
# assert the tag agrees too.

set -euo pipefail
# shellcheck source=lib/common.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

EXPECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) EXPECT="${2:?--expect needs a version}"; shift 2 ;;
    -h|--help) printf 'usage: check-version.sh [--expect X.Y.Z]\n'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_jq

lib_version="$AGENT_OPS_VERSION"
plugin_version=$(jq -r .version "$AO_ROOT/.claude-plugin/plugin.json")
changelog_version=$(grep -m1 -oE '^## \[?[0-9]+\.[0-9]+\.[0-9]+' "$AO_ROOT/CHANGELOG.md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

printf 'scripts/lib/common.sh        %s\n' "$lib_version"
printf '.claude-plugin/plugin.json   %s\n' "$plugin_version"
printf 'CHANGELOG.md                 %s\n' "${changelog_version:-<none>}"
[ -n "$EXPECT" ] && printf 'expected (tag)               %s\n' "$EXPECT"

status=0
if [ "$lib_version" != "$plugin_version" ]; then
  fail "common.sh ($lib_version) != plugin.json ($plugin_version)"
  status=1
fi
if [ -z "$changelog_version" ]; then
  fail "CHANGELOG.md has no '## X.Y.Z' heading"
  status=1
elif [ "$changelog_version" != "$lib_version" ]; then
  fail "CHANGELOG.md ($changelog_version) != common.sh ($lib_version)"
  status=1
fi
if [ -n "$EXPECT" ] && [ "$EXPECT" != "$lib_version" ]; then
  fail "tag ($EXPECT) != declared version ($lib_version)"
  status=1
fi

[ "$status" -eq 0 ] && ok "versions agree"
exit "$status"
