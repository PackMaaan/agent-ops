# Modules

Agent Ops is designed to accumulate capability. This is the guide for adding
your own.

## What qualifies as a module

1. A **git repository** with a stable branch to track.
2. Containing at least one directory with a `SKILL.md` carrying Agent Skills
   frontmatter (`name` and `description`).
3. Whose `description` is specific enough to route on without reading the body.
4. With a license compatible with your redistribution intent.

That is the entire contract. No manifest on the module side, no build step, no
Agent Ops-specific files. Any [Agent Skills](https://agentskills.io)-compatible
repository works as-is — which is exactly why CCPM and the GitHub Project skill
could be composed without either project knowing Agent Ops exists.

### On descriptions

Point 3 is the one that decides whether a module is useful. The agent routes by
reading `description` alone. Compare:

> ❌ `description: "Security tooling."`
>
> ✅ `description: "Security review workflows. Use when auditing code for OWASP Top 10 issues, analysing a CVE's blast radius, reviewing authentication or authorisation logic, or triaging a dependency advisory. Do NOT use for: writing security tests, or configuring branch protection."`

The second one fires when it should and stays quiet when it should not. The
first never fires reliably.

---

## Adding a module

```bash
agent-ops module add \
  --id security-audit \
  --url https://github.com/acme/security-audit-skill.git \
  --branch main \
  --summary "OWASP and CVE review workflows" \
  --license MIT \
  --capability security --capability review
```

The command runs one rollback-protected sequence:

1. `git submodule add --branch <branch> <url> modules/<id>`
2. Auto-detects skills by finding every `SKILL.md` up to four levels deep
3. Validates each source actually has a `SKILL.md`, and that no skill name
   collides with an existing one
4. Inserts the registry entry, keeping builtins first and submodules sorted by id
5. Runs `doctor`

If any step after the submodule add fails, the submodule is removed again —
including its `.git/modules` cache — so a failed add leaves nothing behind.

Then:

```bash
$EDITOR NOTICE.md          # record the license — this is not generated
agent-ops install          # make the skill available in the host repo

git add .gitmodules modules/security-audit registry/modules.json NOTICE.md
git commit -m "feat(modules): add security-audit"
```

### Non-standard layouts

```bash
agent-ops module add --id foo --url https://github.com/acme/foo.git \
  --skill foo=src/agent/skills/foo \
  --skill foo-advanced=src/agent/skills/foo-advanced
```

One module may contribute several skills. Names must be unique across the whole
registry — they become directory names in the host's `.claude/skills/`, and
`module add` refuses a collision rather than silently shadowing.

### Options

| Flag | Purpose |
|---|---|
| `--id` | registry identifier and CLI selector, `^[a-z0-9][a-z0-9-]*$` |
| `--url` | clone URL |
| `--branch` | branch to track (default `main`) |
| `--path` | checkout path (default `modules/<id>`) |
| `--name` | human-readable name |
| `--summary` | one line, shown in `module list` and the host's `AGENTS.md` |
| `--license` | SPDX expression, for `NOTICE.md` |
| `--upstream` | canonical origin when `--url` is a fork |
| `--skill NAME=SRC` | explicit skill mapping, repeatable |
| `--capability CAP` | capability tag, repeatable |
| `--dry-run` | show what would happen |

---

## Updating

```bash
agent-ops module sync              # all enabled submodules
agent-ops module sync ccpm         # one
agent-ops module sync --dry-run
```

Fast-forwards each submodule to its tracked branch tip and reports, per module:
old and new SHA, commit count, the first ten subjects, and a GitHub compare URL.

**It does not commit.** A pinned pointer determines what code runs on every
machine that consumes Agent Ops, so bumping one is a supply-chain decision, not
a maintenance chore:

```bash
agent-ops doctor
git add modules registry/modules.json
git commit -m "chore(modules): bump pinned module revisions"
```

Dirty submodules are skipped rather than force-updated — that state means
someone edited inside `modules/`, which is never correct.

Dependabot (`gitsubmodule` ecosystem) and Renovate (`git-submodules` manager)
are both configured to raise these as individual, never-auto-merged PRs.

---

## Removing

```bash
agent-ops module remove security-audit
agent-ops module remove security-audit --keep-files   # deregister only
```

Unlinks the skills from the host first — while the registry still describes them
— then removes the registry entry, deinitialises the submodule, and clears
`.git/modules/<path>`.

---

## Disabling without removing

Set `"enabled": false` in `registry/modules.json`. The submodule stays pinned and
checked out; `install` and `doctor` ignore it.

For a machine-local override that should not be committed, copy the registry to
`registry/modules.local.json` and edit that. It takes precedence and is
gitignored. `doctor` warns whenever it is in effect.

---

## Invariants

### Never edit inside `modules/`

A submodule checkout is a pinned pointer to someone else's commit. Local edits
are lost on the next sync, invisible to every other consumer, and turn each
future update into a conflict.

| Situation | Correct move |
|---|---|
| Upstream bug | PR upstream; pin your fork via `--url` meanwhile |
| Your own extension | a new module |
| Divergence you must keep | fork, track the fork, record `--upstream` |

### Never hand-edit `.gitmodules` and the registry separately

They are two halves of one fact, and git enforces nothing. CI fails on drift in
either direction. Use `module add` / `module remove`, which write both or
neither.

### The registry is schema-validated

`registry/schema/modules.schema.json` is enforced in CI via `check-jsonschema`.
Submodule entries require `url` and `branch`. Builtin entries must have
`path: "."`. Ids and skill names are constrained because they become filesystem
paths.

CI additionally verifies that every pinned SHA is an ancestor of the branch it
claims to track — catching a pointer that was moved to a commit living only on
someone's fork or a deleted branch.

---

## Candidate modules

The registry shape anticipates these. None are required, and the
`github-project` skill's own "Related Skills" section names several, which makes
them natural first additions.

| Capability gap | Candidate |
|---|---|
| Deep security review — OWASP, CVE analysis | `security-audit` |
| SLSA provenance, SBOM, signed releases | `enterprise-readiness` |
| Branching strategy, conventional commits | `git-workflow` |
| Language-specific CI and lint conventions | one module per language |
| Data platform conventions — dbt, warehouse, BI | your own internal module |

Before adding one, ask where it overlaps with an existing module. Routing
collisions — two skills that both plausibly own a question — are the main way a
composed skill set degrades.
