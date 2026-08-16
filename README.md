# Agent Ops

[![CI](https://github.com/PackMaaan/agent-ops/actions/workflows/ci.yml/badge.svg)](https://github.com/PackMaaan/agent-ops/actions/workflows/ci.yml)
[![Security](https://github.com/PackMaaan/agent-ops/actions/workflows/security.yml/badge.svg)](https://github.com/PackMaaan/agent-ops/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/PackMaaan/agent-ops/badge)](https://scorecard.dev/viewer/?uri=github.com/PackMaaan/agent-ops)
[![Agent Skills](https://img.shields.io/badge/Agent_Skills-compatible-4b3baf)](https://agentskills.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-28a745)](LICENSE)

**One submodule that gives any repository a world-class GitHub setup and the
agent skills to actually ship on top of it.**

Agent Ops composes two proven Agent Skills — [CCPM](https://github.com/automazeio/ccpm)
for spec-driven delivery and the [GitHub Project skill](https://github.com/netresearch/github-project-skill)
for platform configuration — into a single thing you drop into a repo. It is
built to accumulate: adding a third, fourth, or tenth capability is one command.

```bash
git submodule add https://github.com/PackMaaan/agent-ops .agent-ops
git submodule update --init --recursive
.agent-ops/bin/agent-ops install
.agent-ops/bin/agent-ops bootstrap
```

That is a repository with branch protection, CODEOWNERS, issue forms, a security
policy, dependency auto-merge, and three agent skills wired into `.claude/skills/`.

---

## Contents

- [Why this exists](#why-this-exists)
- [What you get](#what-you-get)
- [Install](#install)
- [Commands](#commands)
- [How it is put together](#how-it-is-put-together)
- [Adding your own modules](#adding-your-own-modules)
- [Keeping modules current](#keeping-modules-current)
- [Standards applied to this repo](#standards-applied-to-this-repo)
- [Testing](#testing)
- [Licensing](#licensing)

---

## Why this exists

Both upstream projects are excellent and solve genuinely different halves of the
same problem. CCPM knows how to turn an idea into shipped code with full
traceability. The GitHub Project skill knows how to make a repository behave
correctly under that load — protection rules that actually block, merge methods
that actually agree, review threads that are actually resolved.

Using them together means, today, cloning two repos, symlinking two skill
directories into every project, remembering which one owns which question, and
manually re-syncing both whenever upstream moves.

Agent Ops makes that one submodule, one install command, and one routing skill
that knows which module is authoritative for a given request — without forking
or vendoring either project.

---

## What you get

### Three skills, installed into your repo

| Skill | Source | Handles |
|---|---|---|
| `ccpm` | pinned submodule | PRDs, epics, task decomposition, GitHub sync, parallel agents, standups |
| `github-project` | pinned submodule | branch protection, rulesets, CODEOWNERS, auto-merge, sub-issues, merge queues |
| `agent-ops` | this repo | routing between the two, bootstrap, module management |

### A repository bootstrap that composes rather than duplicates

`agent-ops bootstrap` renders the `github-project` module's own asset templates
where they exist, and only supplies what the module does not cover — issue
*forms* (not markdown templates), release-note grouping, a label taxonomy, editor
config. Branch protection is delegated to the module's own idempotent,
drift-detecting script rather than reimplemented.

### An opt-in GitHub automation layer

Nothing below is on by default — it all acts on your issues and pull requests,
so you ask for it explicitly.

```bash
agent-ops bootstrap --workflows          # PR/issue lifecycle
agent-ops bootstrap --stacked-delivery   # stacked PR templates + planning
agent-ops bootstrap --guardrails         # destructive-git hook
```

| Workflow | What it does |
|---|---|
| `pr-auto-update` | Keeps every open PR current with the base, so conflicts surface small |
| `pr-issue-auto-close` | A merged PR moves its linked issues to `status: done` |
| `pr-status-labels` | Draft state drives the PR's status label |
| `issue-triage` | Fills missing status/priority labels, never overwrites |
| `coderabbit-to-issues` | Review findings become tracked issues, closed when the thread resolves |

All five are gated by `.github/WORKFLOW_KILLSWITCH` — one file, read from the
default branch so a PR cannot flip it, that stops every automation at once.

**Stacked delivery** adds four PR templates (platform/client × full/minimal), an
issue form, and a workflow that comments a generated stack ID and one branch name
per layer. **Guardrails** install a `PreToolUse` hook that refuses destructive git
— checking every segment, so `true; git push` is blocked rather than waved
through, and proving it blocks before wiring itself in.

### Works with Copilot too

`install` writes its managed block into `.github/copilot-instructions.md`
alongside `AGENTS.md` and `CLAUDE.md`, so the repository advertises the same
capabilities whichever agent opens it.

### A registry designed to grow

`registry/modules.json` is schema-validated in CI, and CI fails if it and
`.gitmodules` ever disagree. Adding a capability is:

```bash
agent-ops module add --id security-audit --url https://github.com/acme/security-audit-skill.git
```

---

## Install

### Into an existing repository

```bash
cd your-repo
git submodule add https://github.com/PackMaaan/agent-ops .agent-ops
git submodule update --init --recursive
.agent-ops/bin/agent-ops install
.agent-ops/bin/agent-ops doctor
```

`install` symlinks each module skill into `.claude/skills/`, writes a managed
block into your `AGENTS.md` and `CLAUDE.md`, and adds the generated links to
`.git/info/exclude` so they never show up in `git status`.

Symlinks are deliberate — `git submodule update` is then immediately live with
no reinstall step.

**Tell your collaborators**, because a plain `git clone` gets the submodule
pointer but not its content:

```bash
git clone --recurse-submodules <your-repo>
# or, after cloning:
git submodule update --init --recursive && .agent-ops/bin/agent-ops install
```

### Other harnesses

```bash
agent-ops install --harness factory     # .factory/skills
agent-ops install --harness agents      # .agents/skills
agent-ops install --harness opencode    # .opencode/skills
agent-ops install --harness all
agent-ops install --dest path/to/skills --copy
```

### Requirements

`git`, `bash` (3.2 is supported — macOS ships it), and `jq`. `gh` is needed only
for the bootstrap phases that talk to GitHub. Everything else degrades to a
warning rather than a failure.

Full walkthrough, including standing up a brand-new repository in the correct
order: [`docs/INSTALL.md`](docs/INSTALL.md).

---

## Commands

```text
agent-ops install            Link module skills into the host repository
agent-ops uninstall          Remove what install created
agent-ops bootstrap          Apply GitHub standards to the host repository
agent-ops doctor             Diagnose tooling, registry, and installed state

agent-ops module list        Show the registry and pinned revisions
agent-ops module add         Register a new capability module
agent-ops module remove      Deregister a module and drop its submodule
agent-ops module sync        Update submodules to their tracked branch tips

agent-ops bootstrap --workflows         Install the PR/issue automation
agent-ops bootstrap --stacked-delivery  Install stacked-PR templates + planning
agent-ops bootstrap --guardrails        Install the destructive-git hook
```

Every command supports `--help`. `install`, `uninstall`, `bootstrap`,
`module add`, `module remove`, and `module sync` all support `--dry-run`.

`doctor` is the first move when something is wrong — it separates
"module not checked out" from "registry drift" from "skill not linked", which
look identical from the outside and have three different fixes.

---

## How it is put together

```text
agent-ops/
├── bin/agent-ops              single entry point
├── scripts/                   install, bootstrap, doctor, module lifecycle
│   └── lib/common.sh          host detection, registry access, managed blocks
├── registry/
│   ├── modules.json           the declarative inventory
│   └── schema/                JSON Schema, enforced in CI
├── modules/                   pinned submodules — never edited in place
│   ├── ccpm/
│   └── github-project/
├── skills/agent-ops/          the routing meta-skill
├── templates/
│   ├── github-standards/      files, workflows and labels for host repos
│   └── agent-guardrails/      the destructive-git PreToolUse hook
├── tests/                     143 assertions, no test framework dependency
└── docs/
```

The host repository is found by asking git for the superproject working tree, so
Agent Ops works at any submodule path — `.agent-ops`, `tools/agent-ops`, wherever.
`--target` overrides it for standalone clones and CI.

More detail: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Adding your own modules

Any Agent Skills-compatible git repository qualifies. There is no manifest to
add on the module side and no build step.

```bash
agent-ops module add \
  --id security-audit \
  --url https://github.com/acme/security-audit-skill.git \
  --summary "OWASP and CVE review workflows" \
  --license MIT \
  --capability security --capability review

$EDITOR NOTICE.md          # record the license
agent-ops install
git add .gitmodules modules/security-audit registry/modules.json NOTICE.md
git commit -m "feat(modules): add security-audit"
```

Skills are auto-detected by finding every `SKILL.md` in the checkout; pass
`--skill NAME=SRC` for non-standard layouts. The command rolls the submodule
back if any validation step fails.

Full guide: [`docs/MODULES.md`](docs/MODULES.md).

---

## Keeping modules current

```bash
agent-ops module sync
```

Fast-forwards each submodule to its tracked branch tip and prints, per module,
the SHA range, the commit count, the first ten subjects, and a GitHub compare
URL. It deliberately **does not commit** — bumping a pinned pointer changes what
code runs on every consumer's machine, so the review is the point.

Dependabot and Renovate are both configured to raise submodule bumps as
individual, never-auto-merged PRs for the same reason.

---

## Standards applied to this repo

Agent Ops holds itself to what it installs.

- Branch protection with required conversation resolution and a one-approver baseline
- All GitHub Actions pinned to commit SHAs, with Dependabot and Renovate keeping them current
- Least-privilege `permissions:` on every workflow, `persist-credentials: false` on every checkout
- CodeQL (actions), [zizmor](https://github.com/zizmorcore/zizmor) workflow analysis, gitleaks, OpenSSF Scorecard
- A supply-chain check that rejects any submodule URL that is not `https://github.com/`
- CI on Ubuntu **and macOS** — the macOS leg is what keeps the scripts honest about bash 3.2
- shellcheck, actionlint, markdownlint, yamllint, JSON Schema validation
- Version consistency enforced across `common.sh`, `plugin.json`, and `CHANGELOG.md`

---

## Testing

```bash
bash tests/run.sh              # everything
bash tests/run.sh install      # one file
```

Requires only `git`, `bash`, and `jq`. The suite builds throwaway host
repositories in `mktemp` directories and exercises the real install, bootstrap,
and uninstall paths — including that uninstall leaves host-authored content
untouched, and that a real directory is never clobbered by a symlink.

---

## Licensing

Agent Ops itself is [MIT](LICENSE). The modules are **not vendored** — they are
pinned submodules that keep their own upstream licenses:

| Module | License |
|---|---|
| CCPM | MIT |
| GitHub Project Skill | MIT (code) AND CC-BY-SA-4.0 (content) |

`install` symlinks by default rather than copying, which keeps that boundary
clean. See [`NOTICE.md`](NOTICE.md) for attribution and the implications of
`--copy`.

**CCPM** was developed at [Automaze](https://automaze.io). **GitHub Project
Skill** was developed by [Netresearch](https://www.netresearch.de/). Agent Ops
composes their work; it does not modify or relicense it.
