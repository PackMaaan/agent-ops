#!/usr/bin/env bash
#
# The registry and .gitmodules are two halves of one fact. These tests are what
# make hand-editing either of them a caught error rather than a latent one.

set -uo pipefail
HERE=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=lib.sh
. "$HERE/lib.sh"

printf 'registry\n'

REG="$ROOT/registry/modules.json"

it "registry is valid JSON"
assert_ok jq -e . "$REG"

it "registry declares version 1"
assert_eq "$(jq -r .registryVersion "$REG")" "1"

it "every module id is unique"
total=$(jq '.modules | length' "$REG")
unique=$(jq '[.modules[].id] | unique | length' "$REG")
assert_eq "$unique" "$total"

it "every skill name is unique across all modules"
total_skills=$(jq '[.modules[].skills[].name] | length' "$REG")
unique_skills=$(jq '[.modules[].skills[].name] | unique | length' "$REG")
assert_eq "$unique_skills" "$total_skills"

it "module ids match ^[a-z0-9][a-z0-9-]*$"
bad=$(jq -r '[.modules[].id | select(test("^[a-z0-9][a-z0-9-]*$") | not)] | join(",")' "$REG")
assert_eq "$bad" ""

it "skill names match ^[a-z0-9][a-z0-9-]*$"
bad=$(jq -r '[.modules[].skills[].name | select(test("^[a-z0-9][a-z0-9-]*$") | not)] | join(",")' "$REG")
assert_eq "$bad" ""

it "submodule entries declare url and branch"
bad=$(jq -r '[.modules[] | select(.kind == "submodule") | select((.url | not) or (.branch | not)) | .id] | join(",")' "$REG")
assert_eq "$bad" ""

it "builtin entries use path \".\""
bad=$(jq -r '[.modules[] | select(.kind == "builtin") | select(.path != ".") | .id] | join(",")' "$REG")
assert_eq "$bad" ""

it "every registry submodule has a .gitmodules entry"
missing=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  git -C "$ROOT" config -f .gitmodules --get "submodule.$path.url" >/dev/null 2>&1 || missing="$missing $path"
done < <(jq -r '.modules[] | select(.kind == "submodule") | .path' "$REG")
assert_eq "$missing" ""

it "every .gitmodules entry has a registry entry"
extra=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  jq -e --arg p "$path" '.modules[] | select(.path == $p)' "$REG" >/dev/null 2>&1 || extra="$extra $path"
done < <(git -C "$ROOT" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
assert_eq "$extra" ""

it "every declared skill source contains a SKILL.md"
missing=""
while IFS=$'\t' read -r id path source; do
  full="$ROOT/$( [ "$path" = "." ] && printf '' || printf '%s/' "$path" )$source"
  [ -f "$full/SKILL.md" ] || missing="$missing $id:$source"
done < <(jq -r '.modules[] | select(.enabled) | . as $m | .skills[] | [$m.id, $m.path, .source] | @tsv' "$REG")
assert_eq "$missing" ""

it "every SKILL.md has name and description frontmatter"
bad=""
while IFS=$'\t' read -r id path source; do
  full="$ROOT/$( [ "$path" = "." ] && printf '' || printf '%s/' "$path" )$source/SKILL.md"
  [ -f "$full" ] || continue
  head -20 "$full" | grep -q '^name:' || bad="$bad $id(name)"
  head -20 "$full" | grep -q '^description:' || bad="$bad $id(description)"
done < <(jq -r '.modules[] | select(.enabled) | . as $m | .skills[] | [$m.id, $m.path, .source] | @tsv' "$REG")
assert_eq "$bad" ""

it "NOTICE.md mentions every submodule path"
missing=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  grep -qF "$path" "$ROOT/NOTICE.md" || missing="$missing $path"
done < <(jq -r '.modules[] | select(.kind == "submodule") | .path' "$REG")
assert_eq "$missing" ""

summary
