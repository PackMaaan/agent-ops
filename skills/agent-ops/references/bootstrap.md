# Bootstrap — from nothing to a properly configured repository

Two distinct situations. Identify which one before running anything.

---

## A. Adding Agent Ops to an existing repository

```bash
cd /path/to/host-repo
git submodule add https://github.com/PackMaaan/agent-ops .agent-ops
git submodule update --init --recursive --checkout -- .agent-ops
.agent-ops/bin/agent-ops install
```

`install` is idempotent and does three things:

1. Symlinks each enabled module's skill into `.claude/skills/` (add
   `--harness factory|agents|opencode|all` for other harnesses, or `--dest DIR`).
2. Writes a managed block into the host's `AGENTS.md` and `CLAUDE.md` listing
   what is now available. Content outside the `<!-- BEGIN/END agent-ops -->`
   markers is preserved byte for byte.
3. Adds the generated symlinks to `.git/info/exclude` so they never appear in
   `git status`.

Symlinks are deliberate: a `git submodule update` is immediately live with no
reinstall step. Use `--copy` only on symlink-hostile filesystems, and read
`NOTICE.md` first — copying the `github-project` content brings CC-BY-SA-4.0
share-alike obligations with it.

Verify:

```bash
.agent-ops/bin/agent-ops doctor
```

### For collaborators cloning afterwards

The submodule pointer is committed, but the checkout is not. Every clone needs:

```bash
git clone --recurse-submodules <host-repo-url>
# or, after a plain clone:
git submodule update --init --recursive
.agent-ops/bin/agent-ops install
```

Put those two lines in the host repo's README. This is the single most common
onboarding failure.

---

## B. Standing up a brand-new repository

Order matters. Branch protection references the default branch, so the branch
has to exist on the remote before the remote phase can succeed.

```bash
# 1. Local repo and first commit
mkdir my-project && cd my-project
git init -b main

# 2. Add Agent Ops
git submodule add https://github.com/PackMaaan/agent-ops .agent-ops
git submodule update --init --recursive
.agent-ops/bin/agent-ops install

# 3. Generate the standard files (offline — no API calls yet)
.agent-ops/bin/agent-ops bootstrap --files-only

# 4. Fill in every {{PLACEHOLDER}} the previous step reported, then commit
git add -A && git commit -m "chore: bootstrap repository standards"

# 5. Create the remote and push — the branch ref now exists
gh repo create my-project --public --source=. --remote=origin --push

# 6. Now apply labels, repository settings, and branch protection
.agent-ops/bin/agent-ops bootstrap --labels-only
.agent-ops/bin/agent-ops bootstrap --remote-only

# 7. After the first CI run completes, pin the required status checks
# bash 4+ required; on macOS: /opt/homebrew/bin/bash
bash .agent-ops/modules/github-project/skills/github-project/scripts/init-branch-protection.sh \
  OWNER/REPO --from-current-checks
```

Pin **only checks that run on `pull_request`**. A required check that never runs
on PRs — a scheduled Scorecard job, say — blocks every PR permanently.

Step 7 is separate on purpose: required status check names must match what the
workflows actually produce, and that is unknowable until a run exists. Pinning
guessed names is the single most common cause of permanently stuck PRs.

---

## What bootstrap actually does

Three independently skippable phases. Every phase supports `--dry-run`.

### Phase 1 — files

Renders standard files into the working tree, substituting `{{VAR}}`
placeholders. Existing files are never overwritten without `--force`.

Where the `github-project` module ships an asset template, that template is
used. Agent Ops only supplies what the module does not cover.

| File | Source |
|---|---|
| `SECURITY.md` | github-project asset |
| `CONTRIBUTING.md` | github-project asset |
| `.github/CODEOWNERS` | github-project asset |
| `.github/PULL_REQUEST_TEMPLATE.md` | github-project asset |
| `CODE_OF_CONDUCT.md` | Agent Ops (Contributor Covenant 2.1) |
| `.github/ISSUE_TEMPLATE/*.yml` | Agent Ops (issue *forms*, not markdown) |
| `.github/release.yml` | Agent Ops |
| `.github/dependabot.yml` | **generated** from detected ecosystems |
| `.editorconfig`, `.gitattributes` | Agent Ops |

Variables resolved automatically: `ORG`, `REPO`, `PROJECT`, `SLUG`, `YEAR`,
`DEFAULT_BRANCH`, `SECURITY_EMAIL`, `ECOSYSTEM`, `APPROVALS`, `MERGE_STRATEGY`.
Supply anything else with `--var KEY=VALUE`. Placeholders that survive rendering
are reported per-file — nothing is silently left as `{{SOMETHING}}`.

### Phase 2 — labels

Syncs the taxonomy in `templates/github-standards/labels.json`, including the
`epic`, `task`, and `parallel` labels CCPM relies on. Uses `--force`, so it
updates colours and descriptions on labels that already exist without
destroying issue assignments.

### Phase 3 — remote

Repository settings via `gh repo edit`:

- Merge strategy per `--merge-strategy` (default `merge`, matching the
  github-project skill's history-preserving stance — pass `squash` or `rebase`
  if your team differs)
- Delete branch on merge, allow auto-merge, always suggest updating branches
- Secret scanning + push protection, Dependabot alerts

Branch protection is **delegated** to
`modules/github-project/skills/github-project/scripts/init-branch-protection.sh`,
which owns the drift-detection logic. It applies
`required_conversation_resolution: true` plus a one-approver baseline, is
idempotent, and refuses to clobber deliberate admin choices — it reports drift
rather than silently correcting it.

Exit codes worth recognising:

| Code | Meaning | Fix |
|---|---|---|
| 4 | repository has no commits | push first, re-run `--remote-only` |
| 1 | protection drift on opinionated fields | read the per-field diff; decide deliberately |

---

## Common options

```bash
# See everything that would change, touch nothing
agent-ops bootstrap --dry-run

# Air-gapped / no GitHub credentials
agent-ops bootstrap --no-remote --no-labels

# Squash-merge shop with a two-approver rule
agent-ops bootstrap --merge-strategy squash --approvals 2

# Fill in a template variable the detector cannot know
agent-ops bootstrap --var TEST_COMMAND="pytest -q" --var LANGUAGE=Python

# Re-render everything after changing templates
agent-ops bootstrap --files-only --force
```

---

## Verification

```bash
.agent-ops/bin/agent-ops doctor
```

For the GitHub side, query the API directly. The module ships a
`verify-github-project.sh`, but it exits after its first check because of an
upstream `set -e` / `((PASSED++))` bug — see `troubleshooting.md` for the
diagnosis and the replacement checks.
