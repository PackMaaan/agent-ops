# 1. Compose upstream skills with git submodules, not vendoring

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

Agent Ops combines two existing Agent Skills — CCPM and the GitHub Project skill
— into one installable unit, and must keep accepting more over time.

Three ways to get someone else's skill into this repository:

1. **Vendor** — copy the files in and commit them.
2. **Fetch at install time** — clone or download on demand.
3. **Git submodule** — commit a pointer to a specific upstream commit.

The requirements that decide it:

- A consumer must get a **reproducible** set of skills — the same commit on every
  machine, not "whatever main said today".
- Upstream updates must be **reviewable** as a discrete, auditable event.
- The **licensing boundary** must stay where upstream put it. The
  `github-project` content is CC-BY-SA-4.0, which carries a share-alike
  obligation on derivative works.
- Installation must work **offline** after the initial clone.

## Decision

Pin each module as a git submodule under `modules/`, and describe it in
`registry/modules.json`. Never vendor module content into this repository.

The installer **symlinks** module skills into the host repository rather than
copying them.

## Consequences

### Good

- The pinned SHA is the reproducibility guarantee, and it is visible in `git log`.
- Bumping a module is a one-line diff that a reviewer can turn into a compare
  URL. `agent-ops module sync` prints that URL and deliberately does not commit.
- Upstream keeps its own copyright and license. Nothing here is a derivative
  work, so the CC-BY-SA-4.0 share-alike obligation is never triggered.
- Adding a module requires nothing of the module author — any repository with a
  `SKILL.md` qualifies, which is why both upstreams could be composed without
  either project knowing this one exists.
- Symlinks mean `git submodule update` is live immediately, with exactly one
  copy of each module on disk.

### Bad

- Agent Ops is a submodule containing submodules, so a plain `git clone` of a
  host repository gets pointers without content. This is *the* recurring
  failure, and three things mitigate it: `install` initialises modules itself,
  `doctor` names the condition explicitly, and the docs lead with
  `--recurse-submodules`.
- Symlinks are not universally supported. `--copy` exists for those cases, and
  its licensing consequence is documented in `NOTICE.md`.
- `.gitmodules` and the registry can drift, since git enforces no relationship
  between them. Addressed by writing both atomically in `module add`/`remove`
  and failing CI on any mismatch in either direction.

### Rejected alternatives

**Vendoring** would have made cloning trivial, at the cost of an unreviewable
re-vendor diff on every upstream change, an ambiguous provenance story, and
inheriting the CC-BY-SA-4.0 share-alike obligation for content this project
merely redistributes.

**Fetch at install time** would have removed the nested-submodule friction, but
gives up reproducibility (nothing pins what was fetched), requires network
access at install, and makes the supply chain invisible to `git log` and to
Dependabot.
