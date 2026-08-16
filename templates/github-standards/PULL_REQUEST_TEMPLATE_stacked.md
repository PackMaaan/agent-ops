<!--
Root PR template, installed only when stacked delivery is enabled.

GitHub cannot offer a template picker automatically. Append a template query
parameter to the compare URL to choose one:

  ?template=platform-stack-full.md
  ?template=platform-stack-minimal.md
  ?template=client-stack-full.md
  ?template=client-stack-minimal.md

Full vs minimal:
  full     — multi-layer stack, cross-team impact, contract or generated-artifact
             changes, or explicit dependency and merge-order context needed
  minimal  — a small single-concern change, low risk, straightforward validation

If unsure, start with full and delete what reviewers do not need.
-->

## Summary

<!-- What changed and why. Reviewers read this first. -->

## Stack

- **Stack:** `<id>` or `none` · **Layer:** `<x> of <n>` or `n/a`
- **Depends on:** #`<pr>` or `none` · **Blocks:** #`<pr>` or `none`
- **Merge order:** #`<bottom>` → #`<this>` → #`<top>`

## Scope

**In:**

**Out:**

## Validation

<!-- Commands run and what they proved. "CI is green" alone is not validation. -->

## Checklist

- [ ] One logical change
- [ ] Docs updated in this PR, or explicitly not needed
- [ ] No secrets, tokens, or internal hostnames in the diff
- [ ] Breaking changes labelled `breaking-change` and described above
