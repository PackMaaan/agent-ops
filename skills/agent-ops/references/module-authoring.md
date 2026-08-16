# Module authoring — growing Agent Ops

Agent Ops is designed to accumulate capability modules. Each one is a pinned git
submodule plus a registry entry. Nothing else.

## The contract a module must satisfy

1. It is a **git repository** with a stable branch to track.
2. It contains at least one directory holding a `SKILL.md` with valid Agent
   Skills frontmatter (`name` and `description`).
3. Its `description` is specific enough that an agent can route to it without
   reading the body. This is the single highest-leverage thing about a module —
   a vague description means the skill never fires.
4. It carries a license compatible with your redistribution intent.

That is the whole contract. No build step, no manifest inside the module, no
Agent Ops-specific files. Any Agent Skills-compatible repository qualifies.

## Adding a module

```bash
.agent-ops/bin/agent-ops module add \
  --id security-audit \
  --url https://github.com/acme/security-audit-skill.git \
  --branch main \
  --summary "OWASP and CVE review workflows" \
  --license MIT \
  --capability security --capability review
```

The command performs one sequence and rolls the submodule back if any step
fails:

1. `git submodule add --branch <branch> <url> modules/<id>`
2. Auto-detects skills by finding every `SKILL.md` up to four levels deep, or
   uses the `--skill NAME=SRC` pairs you supplied
3. Validates that each declared source actually contains a `SKILL.md`
4. Inserts the registry entry, keeping builtins first and submodules sorted
5. Runs `doctor`

Then:

```bash
# Record the license obligations
$EDITOR NOTICE.md

# Make the new skill available in the host repository
.agent-ops/bin/agent-ops install

git add .gitmodules modules/security-audit registry/modules.json NOTICE.md
git commit -m "feat(modules): add security-audit"
```

**Always update `NOTICE.md`.** It is the only place the licensing of the
composed whole is recorded, and it is not generated.

### Non-standard layouts

When a repository puts its skill somewhere unexpected, be explicit:

```bash
agent-ops module add --id foo --url ... \
  --skill foo=src/agent/skills/foo \
  --skill foo-advanced=src/agent/skills/foo-advanced
```

One module may contribute several skills. Skill names must be unique across the
whole registry — they become directory names in the host's `.claude/skills/`.

## Updating modules

```bash
agent-ops module sync              # every enabled submodule
agent-ops module sync ccpm         # just one
agent-ops module sync --dry-run    # look, don't touch
```

`sync` fast-forwards each submodule to the tip of its tracked branch and prints,
per module, the old and new SHAs, the commit count, the first ten subjects, and
a GitHub compare URL. It **does not commit**. Bumping a pinned pointer changes
what code runs on every machine that consumes Agent Ops — read the range, then
commit deliberately:

```bash
agent-ops doctor
git add modules registry/modules.json
git commit -m "chore(modules): bump pinned module revisions"
```

Modules with a dirty working tree are skipped rather than force-updated. That is
usually a sign someone edited inside `modules/`, which is never correct — see
the invariant below.

## Removing a module

```bash
agent-ops module remove security-audit
```

Unlinks the skills from the host repository first (while the registry still
describes them), then removes the registry entry, then deinitialises the
submodule and clears `.git/modules/<path>`. Pass `--keep-files` to deregister
without removing the checkout.

## Disabling without removing

Set `"enabled": false` in `registry/modules.json`. The submodule stays pinned
and checked out; `install` and `doctor` ignore it.

For machine-local overrides that should not be committed, copy the registry to
`registry/modules.local.json` and edit that — it takes precedence and is
gitignored. `doctor` warns loudly whenever the overlay is in effect, because a
local overlay that outlives its purpose is a confusing failure mode.

## Invariants

**Never edit inside `modules/`.** A submodule checkout is a pinned pointer to
someone else's commit. Local edits are lost on the next `sync`, invisible to
everyone else, and turn every future update into a conflict. If a module needs
changing:

- Upstream bug → open a PR upstream; pin your fork in the meantime via `--url`
- Your own extension → make it a new module
- Divergence you must keep → fork, track the fork, record it in `--upstream`

**Never hand-edit `.gitmodules` and `registry/modules.json` separately.** They
are two halves of one fact. The `registry` CI job fails on any mismatch in
either direction: a `.gitmodules` entry with no registry entry, or a registry
entry with no `.gitmodules` entry.

**The registry is schema-validated.** `registry/schema/modules.schema.json` is
enforced in CI. Submodule entries require `url` and `branch`; builtin entries
must have `path: "."`. Skill names and module ids are constrained to
`^[a-z0-9][a-z0-9-]*$` because they become filesystem paths.

## Suggested future modules

The registry shape anticipates these; none are required.

| Capability gap | Candidate |
|---|---|
| Deep security review — OWASP, CVE analysis | a `security-audit` skill |
| SLSA provenance, SBOM, signed releases | an `enterprise-readiness` skill |
| Branching strategy, conventional commits | a `git-workflow` skill |
| Language-specific CI and lint conventions | one module per language |
| Data platform conventions — dbt, warehouse, BI | your own internal module |

The `github-project` skill's own "Related Skills" section names several of
these, which makes them natural first additions.
