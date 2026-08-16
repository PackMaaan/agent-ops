---
name: agent-ops
description: "Agent Ops is the composition layer over CCPM and the GitHub Project skill. Use it to (a) stand up a repository to world-class GitHub standards — branch protection, rulesets, CODEOWNERS, issue forms, dependency auto-merge, security policy — and (b) run the full delivery loop on top of that foundation: PRD → epic → GitHub issues → parallel agents → merged code. Use when the user says 'set up this repo properly', 'bootstrap the repo', 'apply GitHub standards', 'add agent-ops to this project', 'install the skills', 'add a new module', 'update the modules', or asks which skill handles a delivery-lifecycle or GitHub-platform question. Also use to decide between the ccpm and github-project skills when the request touches both. Do NOT use for: writing application code, debugging, or CI pipeline authoring for a specific language — those belong to language-specific skills."
---

# Agent Ops

A composition layer, not a replacement. Two capability modules are installed as
pinned git submodules; this skill decides which one is authoritative for a given
request and owns the flows that neither covers alone.

## Routing

Route first, then read. Do not answer platform or delivery questions from memory
when a module owns them.

| The request is about | Authority | Read |
|---|---|---|
| PRDs, epics, task breakdown, standups, parallel agent execution, issue close/merge | **CCPM** | `.claude/skills/ccpm/SKILL.md` |
| Branch protection, rulesets, CODEOWNERS, auto-merge, sub-issues, merge queues, PR-blocked troubleshooting | **github-project** | `.claude/skills/github-project/SKILL.md` |
| Standing a repository up from nothing | **this skill** | `references/bootstrap.md` |
| Adding, updating, or removing a capability module | **this skill** | `references/module-authoring.md` |
| The full arc from empty repo to shipped feature | **this skill** | `references/delivery-loop.md` |
| Something is installed but not working | **this skill** | `references/troubleshooting.md` |

**Boundary rule.** When a request spans both modules — "sync the epic to GitHub
and make sure the PRs can't merge with unresolved threads" — CCPM owns the issue
tree and github-project owns the enforcement. Do the CCPM half first: protection
rules applied before the branch ref exists will fail.

## The two modules

**CCPM** (`modules/ccpm`) — spec-driven delivery. Requirements live in files, not
in chat history. Five phases: plan, structure, sync, execute, track. Deterministic
operations (status, standup, search, validate) run as bash scripts with no token
cost. Project state lives in the host repo's `.claude/prds/` and `.claude/epics/`.

**github-project** (`modules/github-project`) — GitHub platform configuration.
Branch protection, rulesets, the merge-method alignment traps, GraphQL review
thread resolution, sub-issue hierarchies, Dependabot/Renovate auto-merge. Ships
asset templates that Agent Ops renders during bootstrap rather than duplicating.

Both follow the [Agent Skills](https://agentskills.io) standard, which is what
makes composition possible without forking either.

## Commands

Every operation goes through one entry point. Assume it is at the Agent Ops
checkout root — typically `.agent-ops/` inside the host repository.

```bash
.agent-ops/bin/agent-ops install      # link module skills into this repo
.agent-ops/bin/agent-ops bootstrap    # apply GitHub standards to this repo
.agent-ops/bin/agent-ops doctor       # diagnose tooling, registry, install state
.agent-ops/bin/agent-ops module list  # what is registered and at which commit
.agent-ops/bin/agent-ops module sync  # update submodules to their branch tips
.agent-ops/bin/agent-ops module add   # register a new capability module
```

`doctor` is the first move whenever something looks wrong. It distinguishes
"module not checked out" from "registry drift" from "skill not linked", which are
three different fixes.

## Invariants

These hold regardless of which module handles a request.

1. **Files are the source of truth.** Never hold plan state in conversation.
2. **Never edit inside `modules/`.** Those are pinned submodules. Fix upstream,
   or extend via a new module — a local edit is silently lost on the next sync.
3. **Never hand-edit `.gitmodules` and `registry/modules.json` separately.**
   Use `agent-ops module add|remove`; CI fails on drift between the two.
4. **Bumping a submodule pointer is a supply-chain event.** `module sync` prints
   the commit range and compare URL and deliberately stops short of committing.
   Review before you commit the bump.
5. **Branch protection needs a branch.** On a new repo: commit and push first,
   then run the remote phase of bootstrap.
6. **Resolving a review thread means calling the GraphQL mutation**, not merely
   replying to the comment. See the github-project skill.

## Quick recognition

| The user says | Do this |
|---|---|
| "set this repo up properly" / "apply GitHub standards" | `references/bootstrap.md` |
| "add agent-ops to this project" | `references/bootstrap.md` § Adding to an existing repository |
| "the skills aren't showing up" | `agent-ops doctor`, then `references/troubleshooting.md` |
| "add <X> as a module" / "I want a security-audit skill too" | `references/module-authoring.md` |
| "update the modules" / "pull upstream changes" | `agent-ops module sync`, review the range, commit |
| "let's build <feature>" / "write a PRD" | Read the **ccpm** skill |
| "why can't this PR merge?" | Read the **github-project** skill |
| "take this from nothing to shipped" | `references/delivery-loop.md` |
