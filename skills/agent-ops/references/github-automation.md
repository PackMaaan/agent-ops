# GitHub automation

The opt-in layer installed by `agent-ops bootstrap --workflows`,
`--stacked-delivery`, and `--guardrails`. Everything here acts on issues and pull
requests, which is why none of it is on by default.

```bash
agent-ops bootstrap --workflows --labels-only   # workflows need the labels
agent-ops bootstrap --workflows                 # …or run the full thing
agent-ops bootstrap --stacked-delivery
agent-ops bootstrap --guardrails
agent-ops bootstrap --workflows --dry-run       # see it first
```

---

## The killswitch

`.github/WORKFLOW_KILLSWITCH` contains `ENABLED` or `DISABLED`. Every installed
workflow starts with a `guard` job that reads it; every other job in that file
carries `needs: guard` and `if: needs.guard.outputs.enabled == 'true'`.

```bash
printf 'DISABLED\n' > .github/WORKFLOW_KILLSWITCH
git commit -am "chore: pause repository automation" && git push
```

Three properties worth understanding:

- **Absent means enabled.** A repository that never installed the file behaves
  normally; the switch has to be set to `DISABLED` deliberately.
- **It is read from the default branch.** On `pull_request_target` the guard job
  checks out the base, so a pull request cannot enable or disable automation by
  editing the file in its own branch.
- **It stops jobs, not runs.** Runs still appear, showing the guard job and
  skipped dependents. That is deliberate: a silently absent run is
  indistinguishable from a broken trigger.

Use it when automation is misfiring and you need the repository usable *now*,
rather than deleting workflow files and reconstructing them later.

---

## The label vocabulary

Issues and pull requests share one status vocabulary, so a single board query
covers both.

| Axis | Labels | Applied by |
|---|---|---|
| Status | `status: triage` → `backlog` → `ready` → `in-review` → `done` | issue-triage, pr-status-labels, pr-issue-auto-close |
| Priority | `P0` `P1` `P2` `P3` | issue-triage defaults to `P2` |
| Type | `bug` `enhancement` `chore` `refactor` `documentation` `ci` | authors and issue forms |
| Stack | `stack: planning` | the stacked delivery issue form |

The type axis reuses the plain labels rather than adding a `type:` prefixed set,
because `.github/release.yml` groups the changelog by exactly those names.
Two names for one concept is how a taxonomy rots.

**The workflows do not create labels.** Run the labels phase first, or every
`gh issue edit --add-label` silently no-ops:

```bash
agent-ops bootstrap --labels-only
```

---

## Workflows

### `pr-auto-update`

On every push to `main`, updates each open non-draft PR branch to include it.

Conflicts come from divergence windows: the longer a branch trails main, the
bigger the eventual collision. Updating on every push keeps that window one merge
wide, so a conflict surfaces while both sides are small and on the PR that caused
it.

A PR GitHub reports `CONFLICTING` cannot be auto-updated. It gets one comment
naming the local resolution recipe — deduplicated by an HTML marker, so a branch
that stays conflicted for a week is not commented on daily.

> **The token matters.** Branch updates pushed with `GITHUB_TOKEN` do not
> re-trigger the PR's own checks. See *the recursion guard* below.

### `pr-status-labels`

Draft → `status: ready`. Ready for review → `status: in-review`.

Runs on `pull_request_target` because a PR from a fork gets a read-only token on
`pull_request` and cannot label itself. Nothing from the PR is checked out or
executed — the only inputs are the event's own numeric fields, so the elevated
token never meets untrusted code. That distinction is the whole safety argument
for `pull_request_target`; if you extend this workflow, do not break it.

### `pr-issue-auto-close`

On merge, moves every issue referenced by a closing keyword in the PR body to
`status: done` and closes it, then marks the PR shipped.

GitHub already closes the issue. What it does not do is move the status label, so
without this the board drifts out of step with the branch.

### `issue-triage`

Gives a new issue `status: triage` and `P2` — but only when it has no `status:`
or `P?` label already. Gaps only, which is what keeps the issue forms' own
default labels authoritative.

### `coderabbit-to-issues`

CodeRabbit posts each finding as a review comment. A thread is the right place to
*discuss* a finding and the wrong place to *track* one: invisible from a board,
gone when the PR closes, counted by nothing.

Two jobs with different triggers:

- **file** — a CodeRabbit review is submitted; each qualifying unresolved thread
  becomes an issue carrying `<!-- coderabbit-thread:<id> -->` for deduplication.
- **reconcile** — the clock, or a closed PR; issues whose thread now reports
  `isResolved` are closed.

Severity is read from CodeRabbit's own markers — "⚠️ Potential issue" is major,
"🛠️ Refactor suggestion" minor, "🧹 Nitpick" trivial, security wording critical —
and `--min-severity` filters. `workflow_dispatch` is a dry run unless you tick
`write`, so the button is safe to press.

---

## Stacked delivery

A **stack** is a chain of PRs where each layer bases on the one below, so a large
change lands as a sequence of reviewable pieces instead of one unreviewable diff.

`--stacked-delivery` installs:

- Four PR templates under `.github/PULL_REQUEST_TEMPLATE/` — platform and client
  lanes, each full and minimal
- A root `PULL_REQUEST_TEMPLATE.md` that explains how to pick one
- The **Stacked delivery plan** issue form
- `stack-plan-suggestions`, which comments on any `stack: planning` issue with a
  generated stack ID and one branch name per layer, each based on the layer below

GitHub has no template picker. A template is chosen by appending a query
parameter to the compare URL:

```text
https://github.com/OWNER/REPO/compare/main...my-branch?template=platform-stack-full.md
```

Full vs minimal: full for a multi-layer stack, cross-team impact, or a contract
change; minimal for a small single-concern change. If unsure, start full and
delete what reviewers do not need.

The plan comment is regenerated in place whenever the issue is edited, rather
than appended, so the issue does not accumulate stale plans.

---

## Guardrails

`--guardrails` installs `.claude/hooks/block-dangerous-git.sh` and registers it
as a `PreToolUse` Bash hook. It refuses `git push`, `reset --hard`, `clean -f`,
`branch -D`, `checkout .`, `rebase`, `filter-branch`, and `update-ref -d`.

Two design points:

- **Every segment is checked.** A guardrail that only inspects the first command
  is bypassed by `true; git push`. The hook splits on `;`, `&&`, `||`, and `|`
  and classifies each segment.
- **Bootstrap proves it blocks before registering it.** A hook that is wired in
  but broken is worse than no hook: it reads as protection while allowing
  everything.

It is a seatbelt, not a security boundary — anything that can run `bash -c`
defeats it. The real protection is branch protection, which lives on the server.

---

## Traps

These are the ones that cost real time.

### `pull_request_review_thread` is not a workflow trigger

It is a **webhook** event. It does not appear in GitHub's workflow schema, and
listing it under `on:` does not merely fail to fire — an unknown `on:` key stops
the entire workflow file from loading, silently taking every other trigger in
that file with it.

This is why `coderabbit-to-issues` reconciles on a schedule instead. GraphQL
`isResolved` is the source of truth, and the cost of having no event is latency,
not a missed close.

### The recursion guard

**Events produced by `GITHUB_TOKEN` never start another workflow run.** GitHub
does this to stop a workflow from triggering itself forever.

The consequences show up in three places:

| Situation | Symptom |
|---|---|
| `pr-auto-update` pushes to a PR branch | The PR's checks do not re-run and stay stale |
| Dependabot runs on Actions runners | No `pull_request` run is ever created for its PR |
| Any workflow that pushes a commit | Nothing downstream reacts to it |

The fix in each case is a Personal Access Token with `repo` scope, stored as a
secret and used instead of `github.token`. `pr-auto-update` reads
`PR_AUTOUPDATE_TOKEN` for exactly this reason:

```yaml
GH_TOKEN: ${{ secrets.PR_AUTOUPDATE_TOKEN || github.token }}
```

Without it, everything still works — the branch is updated, and checks re-run on
the next human push. With required status checks, that distinction is the
difference between a PR that can merge and one that cannot. See
`troubleshooting.md` → *Dependency PRs never merge*.

### Untrusted input belongs in the environment

A PR title, PR body, or issue body is attacker-controlled text. Interpolating it
directly into a `run:` block places it inside the shell's quoting:

```yaml
# WRONG — an apostrophe ends the quote; a crafted body runs commands
run: echo '${{ github.event.pull_request.body }}' | grep '#'

# RIGHT — the value never passes through the shell parser
env:
  PR_BODY: ${{ github.event.pull_request.body }}
run: printf '%s' "$PR_BODY" | grep '#'
```

Every workflow installed here follows the second form. `zizmor` in the security
workflow catches regressions.

### Concurrency prevents duplicate creation

Two runs racing would each read "no issue exists yet" and both create one — the
exact duplicate a marker lookup exists to prevent, arriving by a route the lookup
cannot see. `coderabbit-to-issues` is serialised repository-wide with
`cancel-in-progress: false`, because cancelling a half-finished creation sweep is
worse than queueing.

### Required checks must actually run on pull requests

A check pinned in branch protection that never runs on a PR blocks every PR
permanently. A scheduled Scorecard job is the usual culprit. Pin from a real PR
run, not from a push run.

---

## Verifying the automation

```bash
# The killswitch is readable and set as expected
cat .github/WORKFLOW_KILLSWITCH

# The labels the workflows depend on exist
gh label list --limit 100 | grep -E 'status:|^P[0-3]|stack:'

# The workflows parse (needs actionlint)
actionlint

# The guardrail actually blocks
printf '%s' '{"tool_input":{"command":"git push origin main"}}' \
  | bash .claude/hooks/block-dangerous-git.sh; echo "exit=$?"   # expect 2

# CodeRabbit filing, without writing anything
bash .github/scripts/coderabbit-to-issues.sh --repo OWNER/REPO --all-open
```
