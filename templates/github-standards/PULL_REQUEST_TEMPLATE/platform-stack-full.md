## Summary

What reusable capability does this PR add? One or two sentences.

## Stack position

- **Stack ID:** `PLATFORM-YYYY-MM-<topic>`
- **Layer:** `<x> of <n>`
- **Base branch:** `<branch this PR merges into>`
- **Head branch:** `<this PR's branch>`
- **Depends on:** #`<pr>` or `none`
- **Blocks:** #`<pr>` or `none`
- **Merge order:** #`<bottom>` → #`<this>` → #`<top>`

> A layer merges only after the one below it lands. If this is layer 1, its base
> is the default branch.

## Scope

**In:**

**Out:** (explicitly, so reviewers do not look for it)

## Contract impact

- [ ] No public interface changed
- [ ] Interface changed — migration path documented below
- [ ] Generated artifacts regenerated, not hand-edited

<!-- If an interface changed: who consumes it, and what must they do? -->

## Validation

<!-- Commands run and what they proved. "CI is green" alone is not validation. -->

## Risk and rollback

- **Blast radius:**
- **Rollback:** <!-- revert this PR alone, or must the whole stack unwind? -->

## Reviewer guidance

- **Read first:**
- **Safe to skim:**
