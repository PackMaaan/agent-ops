# Security Policy

## Reporting a vulnerability

**Do not open a public issue.**

Use [GitHub private vulnerability reporting](https://github.com/PackMaaan/agent-ops/security/advisories/new).

Please include the affected version or commit, steps to reproduce, and the
impact you can demonstrate.

| Stage | Target |
|---|---|
| Acknowledgement | 3 business days |
| Initial assessment | 7 business days |
| Fix or mitigation plan | 30 days for high severity |
| Public disclosure | coordinated, after a fix ships |

You will be credited in the advisory unless you ask otherwise.

## Threat model

Agent Ops runs shell scripts on a developer machine and installs third-party
agent skills into a repository. Two consequences drive the design.

### Submodule pointers are executable content

A module's `SKILL.md` becomes instructions an agent follows, and its scripts
become commands a developer runs. Changing a pinned revision changes what
executes on every machine that consumes Agent Ops.

Mitigations in this repository:

- Submodule URLs are restricted to `https://github.com/` by a CI check —
  `git://`, `ssh://`, and unexpected hosts are rejected outright.
- Every pinned SHA is verified in CI to be an ancestor of the branch it claims
  to track, catching a pointer moved to a commit on a fork or a deleted branch.
- `agent-ops module sync` never commits. It prints the SHA range, commit count,
  subjects, and a compare URL, and stops — the review is the control.
- Dependabot and Renovate raise submodule bumps as individual PRs that are
  explicitly excluded from auto-merge.
- `.gitmodules`, `modules/`, and `registry/` are CODEOWNERS-protected.

### The installer writes into a host repository

`install` and `bootstrap` create files and symlinks outside this repository.

- `install` refuses to replace a path that exists and is not a symlink it owns.
- `uninstall` removes only symlinks whose target it can verify, and only the
  content between its own `<!-- BEGIN/END agent-ops -->` markers.
- `bootstrap` never overwrites an existing file without `--force`.
- Every mutating command supports `--dry-run`.

These are covered by tests, including that a pre-existing directory survives an
install attempt and that host-authored content survives an uninstall.

## Scope

In scope:

- Code in this repository: `bin/`, `scripts/`, `tests/`, `templates/`, `registry/`
- Its GitHub Actions workflows
- The module registry and submodule pinning mechanism

Out of scope — report these upstream, though a heads-up is welcome so the
pinned revision can be moved:

| Component | Report to |
|---|---|
| CCPM skill content or scripts | [automazeio/ccpm](https://github.com/automazeio/ccpm/security) |
| GitHub Project skill content or scripts | [netresearch/github-project-skill](https://github.com/netresearch/github-project-skill/security) |

Also out of scope: findings requiring an already-compromised host, and scanner
output with no demonstrated exploit path.

## Supported versions

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Previous minor | ✅ security fixes only |
| Older | ❌ |

## Safe harbour

We will not pursue legal action against researchers acting in good faith: who
report promptly, avoid privacy violations and service degradation, and allow a
reasonable window to remediate before public disclosure.
