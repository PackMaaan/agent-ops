# Notice — third-party content and licensing

Agent Ops is a **composition layer**. The code and documentation authored in this
repository are MIT licensed (see [`LICENSE`](LICENSE)). The capability modules are
**not vendored** — they are pinned git submodules that retain their own upstream
licenses and copyright.

Nothing in this repository relicenses, sublicenses, or modifies the upstream work.
Removing a submodule removes the corresponding obligations with it.

## Modules

| Module | Path | Pinned source | Upstream origin | License |
|---|---|---|---|---|
| CCPM | `modules/ccpm` | [accepted-warnings/ccpm](https://github.com/accepted-warnings/ccpm) | [automazeio/ccpm](https://github.com/automazeio/ccpm) | MIT |
| GitHub Project Skill | `modules/github-project` | [accepted-warnings/github-project-skill](https://github.com/accepted-warnings/github-project-skill) | [netresearch/github-project-skill](https://github.com/netresearch/github-project-skill) | MIT (code) AND CC-BY-SA-4.0 (content) |

Full license texts live inside each submodule checkout:

```bash
git submodule update --init --recursive
less modules/ccpm/LICENSE
less modules/github-project/LICENSE-MIT
less modules/github-project/LICENSE-CC-BY-SA-4.0
```

## Attribution

- **CCPM** was developed at [Automaze](https://automaze.io).
- **GitHub Project Skill** was developed by [Netresearch DTT GmbH](https://www.netresearch.de/).

Both follow the [Agent Skills](https://agentskills.io) open standard, which is what
makes this composition possible without forking either project.

## Redistribution notes

- The CC-BY-SA-4.0 portion of `github-project` (skill definitions, references,
  documentation) carries a share-alike obligation. If you copy that content into
  your own repository rather than consuming it as a submodule, your derived
  content must be released under CC-BY-SA-4.0 with attribution.
- `scripts/install.sh` defaults to **symlinking** module skills rather than copying
  them, which keeps this boundary clean. `--copy` mode creates derivative copies —
  it is provided for CI and symlink-hostile filesystems, and the license terms
  above then apply to your copy.
