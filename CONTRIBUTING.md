# Contributing

Thanks for helping out. [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) covers the
behavioural expectations; this covers the mechanics.

## Getting set up

```bash
git clone --recurse-submodules https://github.com/PackMaaan/agent-ops.git
cd agent-ops
make init      # if you cloned without --recurse-submodules
make doctor
make test
```

You need `git`, `bash`, and `jq`. Everything else is optional and reported by
`make doctor`.

## Before you start

For anything larger than a typo, **open an issue first**. Proposing a new module
for the registry? Use the module proposal form — it asks the questions that
decide whether a module is a good fit, chiefly where it overlaps with what is
already there.

## The rules that matter here

### Never edit inside `modules/`

Those are pinned submodules. Edits there are lost on the next sync, invisible to
other consumers, and turn every future update into a conflict. Fix it upstream,
or add a new module.

### `.gitmodules` and `registry/modules.json` change together

Always via `agent-ops module add` / `agent-ops module remove`, which write both
or neither. CI fails on drift in either direction.

### Submodule bumps get their own PR

Bumping a pinned pointer changes what runs on every consumer's machine. Paste
the compare URL from `agent-ops module sync` into the PR description, and don't
bundle a bump with unrelated changes.

### bash 3.2 is the target

macOS ships bash 3.2 and `/usr/bin/env bash` finds it. In particular, under
`set -u`, `${#arr[@]}` on an empty array is a fatal error — so use
newline-delimited strings wherever a list can be empty. CI runs the suite on
macOS to enforce this; if you only test on Linux you will not notice.

Two more `set -euo pipefail` traps worth knowing: `grep` exits 1 on no match
(needs `|| true` in a pipeline), and `[ test ] && action` propagates its status
when it is the last statement of a function.

### Composition over duplication

Where the `github-project` module already ships an asset template, render it —
do not write a competing one. Agent Ops only supplies what the modules do not
cover. If you find yourself reimplementing module behaviour, that is a signal to
delegate to the module's own script instead.

## Development workflow

```bash
git checkout -b feat/short-description
# ... change something ...
make check        # version + schema + tests
make lint         # if you have the linters installed
```

The test suite drives the scripts with `--target` against throwaway repositories,
so it tests your **working tree**, not the last commit. One test covers
superproject auto-detection and necessarily uses committed state — it skips
itself cleanly on a repo with no HEAD.

Adding behaviour means adding assertions. `tests/lib.sh` has the helpers; there
is no framework to learn.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/). The history drives
generated release notes.

```text
feat(modules): add security-audit
fix(install): handle a host repo with no .git/info directory
chore(modules): bump pinned module revisions
docs: clarify the bootstrap ordering constraint
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`, `revert`. Useful scopes: `install`, `bootstrap`, `doctor`, `modules`,
`registry`, `skill`.

## Pull requests

1. One logical change per PR.
2. Update docs in the same PR as the behaviour change.
3. `make check` green before requesting review.
4. Fill in the template — reviewers read "Why" first.

All review conversations must be resolved before merge. That is enforced by
branch protection, not by convention, and resolving means clicking resolve (or
calling the GraphQL mutation) — replying is not resolving.

## Releasing

Maintainers only.

1. Bump the version in `scripts/lib/common.sh` and `.claude-plugin/plugin.json`.
2. Add the section to `CHANGELOG.md`.
3. `make version` must pass — it checks all three agree.
4. Tag `vX.Y.Z` and push. The release workflow re-verifies the version against
   the tag, re-runs the suite at the tagged commit, and publishes with the
   pinned module revisions recorded in the notes.
