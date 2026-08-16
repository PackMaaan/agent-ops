<!-- Keep this short. Reviewers read "Why" first. -->

## Why

<!-- The problem this solves. Link the issue: Closes #___ -->

## What changed

<!-- The shape of the change, not a file-by-file listing — the diff covers that. -->

## How it was verified

<!-- `bash tests/run.sh` output, commands run, manual checks. "CI is green" alone is not verification. -->

## Checklist

- [ ] Scope is one logical change
- [ ] `bash tests/run.sh` passes locally
- [ ] Docs updated in this PR (or explicitly not needed)
- [ ] No secrets, tokens, or internal hostnames in the diff

## If this touches modules or the registry

- [ ] `.gitmodules` and `registry/modules.json` were changed together, via `agent-ops module add|remove`
- [ ] `NOTICE.md` records the license of any new module
- [ ] For a pinned-revision bump: the upstream commit range was reviewed, and the range is quoted below

<!--
Submodule bumps change what code runs for every consumer. Paste the compare
URL from `agent-ops module sync` here.
-->
