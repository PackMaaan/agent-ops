# Security Policy

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report privately through one of these channels:

1. [GitHub private vulnerability reporting](https://github.com/{{SLUG}}/security/advisories/new) — preferred
2. Email **{{SECURITY_EMAIL}}**

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce, or a proof of concept
- The affected version or commit
- Any mitigation you are already aware of

## What to expect

| Stage | Target |
|---|---|
| Acknowledgement | within 3 business days |
| Initial assessment | within 7 business days |
| Fix or mitigation plan | within 30 days for high severity |
| Public disclosure | coordinated with the reporter, after a fix ships |

We will keep you informed as the report progresses, and we will credit you in
the advisory unless you ask us not to.

## Supported versions

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Previous minor | ✅ security fixes only |
| Older | ❌ |

## Scope

In scope:

- Code in this repository
- Its release artifacts and CI/CD workflows
- Its documented configuration and defaults

Out of scope:

- Vulnerabilities in third-party dependencies — report those upstream, though
  we appreciate a heads-up so we can pin or patch
- Findings that require an already-compromised host or privileged local access
- Automated scanner output with no demonstrated exploit path

## Safe harbour

We will not pursue or support legal action against researchers who act in good
faith: who report promptly, avoid privacy violations and service degradation,
and give us a reasonable window to remediate before public disclosure.
