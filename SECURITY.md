# Security policy

## Supported versions

Espalier has no release yet. Security fixes go into the `main` branch.

## Reporting a vulnerability

Report a vulnerability privately through GitHub: open the Security tab of
the repository and choose "Report a vulnerability"
(<https://github.com/HelrenPDM/espalier/security/advisories/new>). Please do
not open a public issue, pull request or discussion for it, because every
contribution to this repository is public.

A useful report contains:

- the commit or version you tested,
- the affected component (API route, frontend view, configuration or
  dependency),
- the steps that reproduce the problem, and
- the impact you expect, for example which data an attacker can read or
  change.

Please give the maintainers time to publish a fix before you disclose the
vulnerability.

## Verification target

Account security follows OWASP ASVS 5.0.0 Level 2 and NIST SP 800-63B-4
(AAL2). Section 6 of the [implementation plan](docs/plan/README.md) describes
the controls and the requirements each task covers.
