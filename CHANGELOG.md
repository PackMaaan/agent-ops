# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Module *contents* are versioned upstream; this changelog records when their
pinned revisions move, not what changed inside them. Release notes carry the
pinned SHAs for each release.

## [Unreleased]

## 0.2.0

Adds an opt-in GitHub automation layer, ported and generalised from
[PackMaaan/claude-copilot-skills](https://github.com/PackMaaan/claude-copilot-skills).
Nothing here is enabled by default: every piece acts on issues and pull requests,
so it is requested explicitly or not installed.

### Added

- **`agent-ops bootstrap --workflows`** installs five PR/issue lifecycle
  workflows into the host repository:
  - `pr-auto-update` — keeps every open PR branch current with the base, so a
    conflict surfaces while both sides are still small; comments once, with a
    resolution recipe, on branches it cannot update
  - `pr-issue-auto-close` — a merged PR moves its linked issues to `status: done`
    and marks itself shipped
  - `pr-status-labels` — draft state drives the PR's status label
  - `issue-triage` — fills missing status and priority labels, never overwrites
  - `coderabbit-to-issues` — CodeRabbit findings become tracked issues and close
    themselves when their review thread resolves
- **A killswitch that is actually wired.** `.github/WORKFLOW_KILLSWITCH` gates
  every installed workflow through a `guard` job. Read from the default branch,
  so a pull request cannot flip it. Absent means enabled.
- **`--stacked-delivery`** installs four stacked-PR templates (platform and
  client lanes, full and minimal), a chooser as the root PR template, the
  stacked delivery issue form, and `stack-plan-suggestions` — which comments on
  any `stack: planning` issue with a generated stack ID and one branch name per
  layer, regenerated in place on edit.
- **`--guardrails`** installs a destructive-git `PreToolUse` hook and registers
  it in `.claude/settings.json`. It classifies every segment of a compound
  command, so `true; git push` is blocked rather than waved through, and
  bootstrap proves it blocks before wiring it in.
- **`bash templates/.../coderabbit-to-issues.sh`** — a dependency-free bash and
  GraphQL implementation of the filing and reconciliation logic, with a dry run
  by default.
- **GitHub Copilot support.** `agent-ops install` now writes its managed block
  into `.github/copilot-instructions.md` alongside `AGENTS.md` and `CLAUDE.md`,
  so a repository advertises the same capabilities whichever agent opens it.
  `bootstrap` renders the file; `--no-copilot` opts out.
- **Board label vocabulary** — `status: triage|backlog|ready|in-review|done`,
  `P0`–`P3`, `stack: planning`, `coderabbit`. The type axis deliberately reuses
  the existing `bug`/`enhancement`/`chore` labels, because `.github/release.yml`
  already groups the changelog by exactly those names.
- **`skills/agent-ops/references/github-automation.md`** — the routing target
  for automation questions, including the traps: `pull_request_review_thread` is
  a webhook event and not a workflow trigger (an unknown `on:` key stops the
  whole file loading), the `GITHUB_TOKEN` recursion guard, untrusted input
  belonging in `env:` rather than `${{ }}`, and concurrency as duplicate
  prevention.
- CI now lints the workflow templates with actionlint by staging them where it
  looks, and asserts the guardrail's behaviour on 31 cases.

### Changed

- `troubleshooting.md` now names the **mechanism** behind Dependabot PRs never
  receiving a `pull_request` run, which 0.1.0 could only describe: events
  produced by `GITHUB_TOKEN` never start another workflow run, so a bot whose
  branch push uses that token gets no CI. A PAT is the remedy, and is now listed
  first among the workarounds.
- This repository adopts `pr-auto-update`, `pr-issue-auto-close`,
  `pr-status-labels`, `issue-triage` and the killswitch on itself.

## 0.1.0

Initial release.

### Added

- **Composition layer** over two Agent Skills, installed as pinned git
  submodules rather than vendored:
  - [`ccpm`](https://github.com/accepted-warnings/ccpm) — spec-driven delivery:
    PRD → epic → GitHub issues → parallel agents → shipped code
  - [`github-project`](https://github.com/accepted-warnings/github-project-skill) —
    branch protection, rulesets, CODEOWNERS, auto-merge, sub-issues
- **`agent-ops` meta-skill** that routes between the two modules and owns the
  flows neither covers alone: repository bootstrap, module authoring, the
  end-to-end delivery loop, and troubleshooting.
- **`agent-ops` CLI** with `install`, `uninstall`, `bootstrap`, `doctor`, and
  `module list|add|remove|sync`. Every mutating command supports `--dry-run`.
- **Module registry** (`registry/modules.json`) with a JSON Schema, drift
  detection against `.gitmodules` in both directions, and a local overlay for
  machine-specific overrides.
- **Installer** that symlinks module skills into `.claude/skills/` (or
  `.agents`, `.factory`, `.opencode`, or any `--dest`), writes a reversible
  managed block into the host's `AGENTS.md` and `CLAUDE.md`, and excludes the
  generated links from `git status`. `--copy` mode for symlink-hostile
  filesystems.
- **Bootstrap** that applies world-class GitHub standards to the host
  repository in three independently skippable phases — files, labels, remote —
  rendering the `github-project` module's own asset templates where they exist
  and delegating branch protection to its idempotent, drift-detecting script.
- **Host detection** via the git superproject, so Agent Ops works at any
  submodule path with no configuration.
- **Test suite** of 70+ assertions with no framework dependency, exercising
  real install, bootstrap, and uninstall paths against throwaway repositories.

### Repository standards applied to this repo

- All GitHub Actions pinned to commit SHAs; Dependabot and Renovate configured
  to keep them current and to raise submodule bumps as individual,
  never-auto-merged PRs.
- Least-privilege `permissions:` on every workflow; `persist-credentials: false`
  on every checkout.
- CodeQL (actions), zizmor workflow analysis, gitleaks, OpenSSF Scorecard.
- A supply-chain check rejecting any submodule URL that is not
  `https://github.com/`.
- CI on Ubuntu and macOS — the macOS leg enforces bash 3.2 compatibility.
- shellcheck, actionlint, markdownlint, yamllint, JSON Schema validation, and
  version consistency across `common.sh`, `plugin.json`, and this file.

[Unreleased]: https://github.com/PackMaaan/agent-ops/compare/v0.1.0...HEAD
