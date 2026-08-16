# The delivery loop — empty repo to merged feature

The composed arc across both modules. Each step names its authority; read that
module's own reference before executing, rather than working from this summary.

```text
  ┌─ agent-ops ─────────────────────────────────────────────────────────┐
  │  0. Foundation      bootstrap: standards, protection, labels        │
  └──────────────────────────┬──────────────────────────────────────────┘
                             │
  ┌─ ccpm ──────────────────▼───────────────────────────────────────────┐
  │  1. Plan            brainstorm → PRD          .claude/prds/<x>.md   │
  │  2. Structure       PRD → epic → tasks        .claude/epics/<x>/    │
  │  3. Sync            tasks → GitHub issues     epic + sub-issues     │
  └──────────────────────────┬──────────────────────────────────────────┘
                             │
  ┌─ github-project ────────▼───────────────────────────────────────────┐
  │  3b. Hierarchy      addSubIssue GraphQL       real parent/child     │
  └──────────────────────────┬──────────────────────────────────────────┘
                             │
  ┌─ ccpm ──────────────────▼───────────────────────────────────────────┐
  │  4. Execute         parallel agents           one worktree, N streams│
  │  5. Track           standup / next / blocked  bash, no token cost   │
  └──────────────────────────┬──────────────────────────────────────────┘
                             │
  ┌─ github-project ────────▼───────────────────────────────────────────┐
  │  6. Land            resolve threads, merge    GraphQL + merge queue │
  └─────────────────────────────────────────────────────────────────────┘
```

---

## 0. Foundation — `agent-ops`

Once per repository. See `bootstrap.md`.

The load-bearing outcome is `required_conversation_resolution: true` on the
default branch. Everything downstream — parallel agents opening PRs, dependency
bots auto-merging — is only safe because that rule is structurally enforced
rather than documented.

Do this **before the first PR**. Retrofitting protection onto a repo with open
PRs means those PRs skip the rule.

## 1–2. Plan and structure — CCPM

> "I want to build a notification system — push, email, in-app"

CCPM brainstorms before writing, then produces `.claude/prds/<name>.md`. Parsing
that PRD yields a technical epic; decomposing the epic yields numbered task
files carrying `depends_on`, `parallel`, and `conflicts_with` metadata.

These files live in the **host repository**, not in Agent Ops. Agent Ops
contributes the skill; the project state belongs to the project.

## 3. Sync — CCPM, with github-project for hierarchy

CCPM creates the epic issue and one sub-issue per task, renames local task files
to match issue numbers, and sets up a dedicated worktree at `../epic-<name>/`.

Real parent/child relationships need the GraphQL `addSubIssue` mutation — the
`gh` CLI does not support sub-issues. CCPM uses the `gh-sub-issue` extension
when present and falls back to task lists when it is not:

```bash
gh extension install yahsan2/gh-sub-issue
```

`agent-ops doctor` warns when it is missing. For the raw GraphQL — and for the
8-level, 100-children limits — read the github-project skill's
`references/sub-issues.md`.

Apply the labels bootstrap created: `epic` on the parent, `task` on children,
`parallel` on tasks safe to run concurrently. Release notes grouping and the
`next`/`blocked` queries both read them.

## 4. Execute — CCPM

> "start working on issue 1235"

CCPM analyses the issue for independent work streams and launches one agent per
stream, each scoped to its own files, all inside the epic worktree. Agents
commit as `Issue #N: description` and coordinate through git.

The worktree matters: parallel agents on one branch in one working directory
conflict constantly. `../epic-<name>/` gives the epic clean isolation from
whatever else is in flight.

## 5. Track — CCPM

> "standup" · "what's next" · "what's blocked"

Bash scripts reading `.claude/epics/`. Instant, deterministic, zero token cost.
Prefer them over asking the model to summarise state — the scripts cannot
hallucinate progress.

## 6. Land — github-project

The step most often done wrong. **Addressing review comments means two things**:
fixing the code *and* calling `resolveReviewThread` on each thread. Replying is
not resolving, and branch protection blocks on the unresolved flag, not on
whether a reply exists.

```bash
# List unresolved threads, resolve by ID, verify none remain
# → github-project SKILL.md § Programmatic Review Thread Resolution
```

When merges do not happen automatically, the cause is almost always one of:

| Symptom | Cause |
|---|---|
| "Merge method X is not allowed" | workflow merge flag ≠ repository setting |
| "Required status check is expected" | check name ≠ the name the workflow produces |
| `--auto` fails outright | no branch protection configured |
| queued PRs never process | `enqueuePullRequest` given a `mergeMethod` argument it does not accept |

All four are diagnosed in the github-project skill's auto-merge troubleshooting
section. Do not guess — the check-name mismatch in particular looks identical to
a CI failure from the PR page.

## Closing the loop

> "close issue 1235" · "merge the notification-system epic"

CCPM updates local files and GitHub together, then merges the epic worktree back
and cleans it up. The audit trail — PRD → epic → issue → commit → PR → release
note — is complete without anyone having written a status report.

---

## Where responsibility actually sits

| Concern | Owner | Not |
|---|---|---|
| What we are building and why | CCPM PRD | a chat message |
| Which tasks can run in parallel | CCPM task frontmatter | agent judgement |
| Whether a PR may merge | branch protection | reviewer discipline |
| Whether a thread is resolved | GraphQL mutation | a reply comment |
| What version of a module runs | pinned submodule SHA | a floating branch |
| Which skills an agent can see | `registry/modules.json` | ambient config |
