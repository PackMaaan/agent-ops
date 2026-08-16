# GitHub Copilot instructions

Repository-wide guidance for GitHub Copilot. Copilot reads this file
automatically; other agents read `AGENTS.md`. Keep the two consistent — the
Agent Ops managed block below is generated from the same module registry that
produces the `AGENTS.md` block, so both harnesses see the same capabilities.

## Tone

Be concise, explicit, and expert-level. No conversational filler.

## Git standards

- **Conventional Commits** for every commit: `feat:`, `fix:`, `docs:`, `chore:`,
  `refactor:`, `test:`, `ci:`, `build:`, `perf:`, `revert:`.
- **Branch naming:** `<type>/<ticket>-<short-description>`, e.g.
  `feat/ENG-142-connector-retry`.
- Never push directly to the default branch. It is protected; open a PR.
- Never bypass repository guardrails for destructive git operations.

## Pull requests

- One logical change per PR. Update docs in the same PR as the behaviour change.
- **Resolving a review thread means calling the resolve mutation**, not merely
  replying. Branch protection blocks on the unresolved flag, not on whether a
  reply exists.
- All conversations must be resolved before merge. This is enforced structurally.

## Labels

Issues and PRs share one status vocabulary so a single board query shows both:

| Kind | Values |
|---|---|
| Status | `status: triage`, `status: backlog`, `status: ready`, `status: in-review`, `status: done` |
| Priority | `P0`, `P1`, `P2`, `P3` |
| Type | `type: bug`, `type: enhancement`, `type: chore` |

## Testing

Every behaviour change needs a paired test. Prefer fast, focused tests that
exercise real behaviour over mocks that assert the implementation.
