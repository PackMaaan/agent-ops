# Contributing to {{PROJECT}}

Thanks for helping out. This guide covers the mechanics; read
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for the behavioural expectations.

## Before you start

For anything larger than a typo, **open an issue first**. A short design
conversation is cheaper than a rejected pull request. If the change is small
and obvious, go straight to a PR.

## Development workflow

```bash
git clone https://github.com/{{SLUG}}.git
cd {{REPO}}
git checkout -b feat/short-description
```

Branch naming follows the change type: `feat/`, `fix/`, `docs/`, `chore/`,
`refactor/`, `ci/`.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<optional scope>): <description>

[optional body explaining *why*, not *what*]

[optional footer, e.g. "Closes #42" or "BREAKING CHANGE: ..."]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`.

The commit history drives generated release notes, so a clear subject line is
doing real work — it is not ceremony.

## Pull requests

1. Keep the diff focused. One logical change per PR.
2. Update documentation in the same PR as the behaviour change.
3. Make sure CI is green before requesting review.
4. Fill in the PR template — the "why" section is the one reviewers read first.

### Review expectations

- At least **{{APPROVALS}}** approving review is required.
- **All review conversations must be resolved before merge.** This is enforced
  by branch protection, not by convention.
- Address feedback with follow-up commits rather than force-pushing, so
  reviewers can see what changed. Squashing happens at merge time.

## Reporting bugs

Use the [bug report form](https://github.com/{{SLUG}}/issues/new?template=bug_report.yml).
A minimal reproduction is worth more than a long description.

## Reporting vulnerabilities

Do not open a public issue. Follow [`SECURITY.md`](SECURITY.md).

## Questions

Open a [Discussion](https://github.com/{{SLUG}}/discussions). Issues are for
actionable, confirmed work.
