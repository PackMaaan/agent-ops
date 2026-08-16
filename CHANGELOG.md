# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Module *contents* are versioned upstream; this changelog records when their
pinned revisions move, not what changed inside them. Release notes carry the
pinned SHAs for each release.

## [Unreleased]

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
