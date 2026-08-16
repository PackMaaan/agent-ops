# Architecture

Agent Ops is a composition layer. It owns almost no capability of its own — its
job is to make other people's capabilities installable, discoverable, and
updatable as one unit.

## The shape

```text
┌─ host repository ──────────────────────────────────────────────┐
│                                                                │
│  .claude/skills/                                               │
│    ccpm            ─────────┐  (relative symlinks)             │
│    github-project  ───────┐ │                                  │
│    agent-ops       ─────┐ │ │                                  │
│                         │ │ │                                  │
│  AGENTS.md   ← managed block listing what is available         │
│  CLAUDE.md   ← same                                            │
│                         │ │ │                                  │
│  .agent-ops/  (git submodule)                                  │
│    ├── skills/agent-ops ┘ │ │                                  │
│    ├── modules/           │ │                                  │
│    │   ├── github-project ┘ │  (git submodule)                 │
│    │   └── ccpm ────────────┘  (git submodule)                 │
│    ├── registry/modules.json   the inventory                   │
│    └── bin/agent-ops           the entry point                 │
│                                                                │
│  .claude/prds/    ← CCPM project state lives in the HOST       │
│  .claude/epics/                                                │
└────────────────────────────────────────────────────────────────┘
```

Two things that follow from this diagram and are easy to get wrong:

1. **Project state belongs to the host, not to Agent Ops.** CCPM writes PRDs and
   epics into the host's `.claude/`. Agent Ops contributes the skill; the work
   product belongs to the project.
2. **Skills are symlinks into submodules.** Nothing is copied, so a
   `git submodule update` is live immediately, and there is exactly one copy of
   each module on disk.

## Nested submodules

Agent Ops is a submodule that contains submodules. This is the design's main
cost, and it produces exactly one recurring failure: a plain `git clone` of the
host gets the pointers but not the content.

Everything mitigates that same failure:

- `install` detects uninitialised modules and runs `submodule update --init --recursive` itself
- `doctor` distinguishes "not checked out" from every other failure by name
- the README and `docs/INSTALL.md` both lead with `--recurse-submodules`

The alternative — vendoring the module contents into this repository — was
rejected. It would mean re-vendoring on every upstream change, an unreviewable
diff each time, and taking on the CC-BY-SA-4.0 share-alike obligation for the
`github-project` content. Submodules keep the licensing boundary exactly where
upstream put it.

## Host detection

`ao_host_root()` in `scripts/lib/common.sh` resolves the host repository in
priority order:

1. `AGENT_OPS_HOST` / `--target` — explicit, used by tests and standalone clones
2. `git rev-parse --show-superproject-working-tree` — the intended layout
3. the nearest enclosing repository that is not Agent Ops itself

Step 2 is why the submodule path does not matter. `.agent-ops`, `tools/agent-ops`,
`vendor/agent-ops` all work identically, and nothing needs configuring.

`AO_ROOT` is resolved by walking `BASH_SOURCE` through symlinks, so
`bin/agent-ops` can be symlinked onto `PATH` and still find its own repository.

## The registry

`registry/modules.json` is the single source of truth for what is installed.
Every operation reads it; nothing scans the filesystem to discover modules.

```jsonc
{
  "registryVersion": 1,
  "modules": [
    {
      "id": "ccpm",              // CLI selector, must be filesystem-safe
      "kind": "submodule",       // or "builtin" for skills shipped here
      "path": "modules/ccpm",    // relative to AO_ROOT
      "url": "...", "branch": "main",
      "upstream": "...",         // canonical origin when url is a fork
      "enabled": true,
      "license": "MIT",
      "skills": [{ "name": "ccpm", "source": "skill/ccpm" }]
    }
  ]
}
```

`source` is relative to `path`, which is why a module needs no Agent Ops-specific
file: whatever layout upstream chose is described here instead of imposed there.

### Why JSON and not YAML

`jq` is a single, universally packaged binary. A YAML registry would mean either
a `yq` dependency or a hand-rolled parser, and the registry is read by every
command including `doctor` — the one thing that must work when everything else is
broken.

### Drift protection

`.gitmodules` and the registry are two halves of one fact, and nothing in git
keeps them consistent. Three things do:

- `agent-ops module add|remove` writes both, or neither (the submodule is rolled
  back if registry validation fails)
- `tests/test_registry.sh` checks both directions — orphaned `.gitmodules`
  entries *and* orphaned registry entries
- the `registry` CI job runs that test plus JSON Schema validation, and verifies
  every pinned SHA is actually an ancestor of the branch it claims to track

### Local overlay

`registry/modules.local.json` takes precedence when present, and is gitignored.
It lets one machine disable a module without touching tracked files. `doctor`
warns whenever it is in effect — a stale overlay is a genuinely confusing
failure mode, so it is never silent.

## Managed blocks

`install` writes into the host's `AGENTS.md` and `CLAUDE.md`, which are
host-owned files that may already have content. The block markers make the
edit reversible:

```markdown
<!-- BEGIN agent-ops (managed) -->
...generated table of available skills...
<!-- END agent-ops (managed) -->
```

`ao_write_managed_block` replaces only what is between the markers, appending the
block if it is absent. `ao_remove_managed_block` strips it and leaves everything
else byte for byte. Both are covered by tests that assert host-authored lines
survive an install/uninstall round trip.

## Bootstrap: composition over duplication

The rule is that the `github-project` module is authoritative for anything it
already ships. `bootstrap-repo.sh` declares, per file, a candidate list:

```bash
render "SECURITY.md" "$GP_ASSETS/SECURITY.md.template" "$OWN/SECURITY.md"
```

The module's asset wins; the Agent Ops template is a fallback for when the
submodule is not checked out. Where the module ships nothing — issue *forms*,
release-note grouping, the label taxonomy — Agent Ops supplies the original.

Branch protection is not reimplemented at all. It shells out to the module's
`init-branch-protection.sh`, which owns the idempotence and drift-detection
logic, and whose exit codes are translated into actionable messages.

`dependabot.yml` is the one file that is *generated* rather than templated,
because the useful output is one block per detected ecosystem and a template can
only hold one `{{ECOSYSTEM}}` hole.

## Portability constraints

**bash 3.2.** macOS ships it, and `/usr/bin/env bash` finds it. Under `set -u`,
bash 3.2 treats an empty array as unset, so `${#arr[@]}` is a fatal error. The
scripts use newline-delimited strings wherever a list can be empty. CI runs the
suite on macOS specifically to keep this honest — dropping that leg would let
bash-4-isms in within a release.

**No GNU coreutils.** `realpath --relative-to` and `readlink -f` do not exist on
macOS, so `ao_relpath` is implemented in pure shell.

**`set -euo pipefail` everywhere**, which makes two patterns load-bearing:
`grep` returning 1 on no-match must be `|| true`, and `[ test ] && action` as the
last statement of a function will propagate its status.

## What Agent Ops deliberately does not do

- **Modify module content.** `modules/` is read-only by convention, enforced by
  `module sync` refusing to update a dirty submodule.
- **Auto-commit submodule bumps.** `sync` prints the range and stops. The review
  is the security control.
- **Vendor or relicense.** See `NOTICE.md`.
- **Own delivery or platform knowledge.** Every such question routes to a module.
  When Agent Ops starts answering them directly, the composition has failed.
