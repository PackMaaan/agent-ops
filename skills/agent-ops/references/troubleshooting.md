# Troubleshooting

Run `agent-ops doctor` first. It separates the three failure classes that look
identical from the outside: module not checked out, registry drift, skill not
linked.

---

## Skills do not appear to the agent

**`modules/<id>` is empty.** The submodule pointer is committed but the content
is not. This is what a plain `git clone` produces.

```bash
git submodule update --init --recursive
.agent-ops/bin/agent-ops install
```

**The symlink exists but points nowhere.** Usually a module was moved or removed
without re-running install.

```bash
agent-ops doctor          # reports the broken link
agent-ops install         # recreates it
```

**Installed into the wrong directory.** The default is `.claude/skills/`. Other
harnesses look elsewhere:

```bash
agent-ops install --harness factory     # .factory/skills
agent-ops install --harness agents      # .agents/skills
agent-ops install --harness all
agent-ops install --dest path/to/skills # anything else
```

**The harness does not follow symlinks.** Rare, but real in some sandboxes and
on Windows without developer mode:

```bash
agent-ops install --copy
```

Read `NOTICE.md` before doing this — copying `github-project` content brings
CC-BY-SA-4.0 share-alike obligations.

---

## `could not determine the host repository`

Agent Ops resolves its host by asking git for the superproject working tree.
That fails when Agent Ops is cloned standalone rather than added as a submodule.

```bash
# Point at a target explicitly
agent-ops install --target /path/to/host-repo

# Or, equivalently
AGENT_OPS_HOST=/path/to/host-repo agent-ops install
```

If you meant to add it as a submodule:

```bash
cd /path/to/host-repo
git submodule add https://github.com/PackMaaan/agent-ops .agent-ops
```

---

## `registry entry has no .gitmodules entry` (or the reverse)

The two files drifted, which means someone hand-edited one of them. CI fails on
this deliberately.

```bash
# Inspect both sides
agent-ops module list
git config -f .gitmodules --get-regexp '^submodule\..*\.path$'
```

Repair by removing the half-registered module and re-adding it properly:

```bash
agent-ops module remove <id> --keep-files   # drop the registry entry
agent-ops module add --id <id> --url ...    # re-add both halves atomically
```

---

## `agent-ops: jq: command not found`

The registry is JSON and `jq` reads it.

```bash
brew install jq          # macOS
sudo apt-get install jq  # Debian/Ubuntu
```

---

## Bootstrap wrote files full of `{{PLACEHOLDER}}`

Expected, and reported per file as it happens. Some variables cannot be
detected — test commands, language names, binary names. Supply them:

```bash
agent-ops bootstrap --files-only --force \
  --var LANGUAGE=Python \
  --var TEST_COMMAND="pytest -q" \
  --var INSTALL_COMMAND="uv sync"
```

Or edit the rendered files directly; they are yours now, and bootstrap will not
overwrite them again without `--force`.

---

## Branch protection did not apply

**Exit code 4 — the repository has no commits.** The default branch ref must
exist before it can be protected.

```bash
git push -u origin main
agent-ops bootstrap --remote-only
```

**Exit code 1 — drift detected.** The module found existing protection settings
that differ from its baseline on opinionated fields. It prints a per-field diff
and refuses to overwrite: an admin may have set those deliberately. Read the
diff and decide, rather than forcing.

**`gh repo edit` failed.** You need admin permission on the repository. Check
with `gh api repos/OWNER/REPO --jq .permissions`.

---

## Dependency PRs never merge

**"GitHub Actions is not permitted to approve pull requests."** The repository
requires an approving review, and `GITHUB_TOKEN` is not allowed to give one, so
every Dependabot and Renovate PR stalls. `agent-ops bootstrap --remote-only`
sets this; to fix it by hand:

```bash
gh api repos/OWNER/REPO/actions/permissions/workflow --method PUT \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=true
```

Workflow permissions stay read-only — only the approval bit changes.

**Major version bumps.** These are intentionally left for a human, and the
workflow comments on the PR saying so. Merge them yourself after reading the
changelog.

---

## Known defects in the github-project module's scripts

These are upstream's code. **Do not edit anything under `modules/`** — fix them
upstream and re-pin, or work around them as below.

### `mapfile: command not found`

`mapfile` is bash 4+; macOS ships bash 3.2. Run the script under a newer bash:

```bash
brew install bash
/opt/homebrew/bin/bash modules/github-project/skills/github-project/scripts/init-branch-protection.sh \
  OWNER/REPO --from-current-checks
```

Agent Ops' own scripts target bash 3.2 and need none of this.

### `verify-github-project.sh` stops after the first check

It prints "README.md exists" immediately followed by "README.md missing", then
exits. The cause is `set -e` combined with `((PASSED++))`: post-increment
evaluates to the *old* value, so when the counter is 0 the arithmetic command
returns exit status 1. That makes `pass()` look like a failure — the `||`
branch fires — and then `fail()` does the same thing and terminates the script.
It reproduces on every platform, not just macOS.

Until it is fixed upstream, verify the GitHub side directly:

```bash
# Files bootstrap should have created
ls SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md \
   .github/CODEOWNERS .github/dependabot.yml .github/release.yml \
   .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/

# Repository settings
gh api repos/OWNER/REPO --jq '{allow_merge_commit, allow_squash_merge,
  allow_rebase_merge, delete_branch_on_merge, allow_auto_merge,
  allow_update_branch, has_issues, has_discussions}'

# Branch protection
gh api repos/OWNER/REPO/branches/main/protection --jq '{
  checks: .required_status_checks.contexts,
  approvals: .required_pull_request_reviews.required_approving_review_count,
  conversation: .required_conversation_resolution.enabled,
  force_push: .allow_force_pushes.enabled}'

# Actions may approve PRs (required for dependency auto-merge)
gh api repos/OWNER/REPO/actions/permissions/workflow
```

`init-branch-protection.sh` itself is sound — its second run reports drift
rather than clobbering, which is the behaviour Agent Ops delegates to.

---

## PRs cannot merge after bootstrap

Branch protection is now enforcing what was previously advisory. The three usual
causes:

| Message | Fix |
|---|---|
| unresolved conversations | resolve threads via GraphQL — replying is not resolving |
| required status check expected but not found | check names were pinned before CI ever ran |
| merge method not allowed | workflow flag disagrees with the repository setting |

For required status checks, pin them from a real run rather than guessing:

```bash
bash .agent-ops/modules/github-project/skills/github-project/scripts/init-branch-protection.sh \
  OWNER/REPO --from-current-checks
```

Full diagnosis lives in the github-project skill's troubleshooting sections.

---

## A module has local modifications

`module sync` skips dirty submodules rather than force-updating them. Editing
inside `modules/` is never correct — those changes are invisible to every other
consumer and lost on the next sync.

```bash
git -C modules/<id> diff        # see what changed
git -C modules/<id> checkout .  # discard
```

If the change is genuinely needed, upstream it or fork and re-pin with
`--url <your-fork>`, recording the canonical source via `--upstream`.

---

## Uninstalling

```bash
agent-ops uninstall                 # remove symlinks and managed blocks
agent-ops uninstall --purge         # also remove --copy'd directories

# Then remove Agent Ops itself
git submodule deinit -f .agent-ops
git rm -f .agent-ops
rm -rf .git/modules/.agent-ops
```

`uninstall` only removes symlinks it owns and the content between the
`<!-- BEGIN/END agent-ops -->` markers. Files you wrote — including everything
`bootstrap` generated — are left alone, because they are yours.
