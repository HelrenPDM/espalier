# Architecture diagrams

The diagrams are PlantUML sources. They describe the target state that the
[implementation plan](../plan/README.md) builds towards. Each diagram has one
purpose.

| File | Type | Shows |
|---|---|---|
| [`context.puml`](context.puml) | component | System context, Phoenix contexts, vault, rate limiter, SPA, identity providers, external LMS, downstream systems |
| [`domain-catalog.puml`](domain-catalog.puml) | class | Catalog and content: program, stations, segments, qualifications, modules, lessons, blocks, rules, items, assessments, companion formats, glossary, sources, learning objectives with their links to lessons, items and companion formats |
| [`domain-records.puml`](domain-records.puml) | class | Accounts and authentication, policies, person-linked records, anonymous insights |
| [`domain-values.puml`](domain-values.puml) | class | Enumerations used by both domain diagrams |
| [`learner-journey.puml`](learner-journey.puml) | activity | Path selection, objectives of the topic, lessons, reveal on wrong answer, exam pass rule, evidence of the objectives at module completion, credential |
| [`credential-lifecycle.puml`](credential-lifecycle.puml) | state | Issue, refresher, expiry and revocation of a credential |
| [`auth-local.puml`](auth-local.puml) | sequence | Invitation with passkey enrollment, passkey sign-in with conditional UI, password with a second factor (TOTP, passkey or recovery code) |
| [`auth-oidc.puml`](auth-oidc.puml) | sequence | OIDC sign-in with `oidcc` (Entra ID / Microsoft 365, Google Workspace, other): intents for linking and step-up bound to the creating session, sign-in ticket bound to the transaction cookie, the answers of the finish step, RP-initiated and front-channel logout |
| [`auth-ldap.puml`](auth-ldap.puml) | sequence | LDAP / Active Directory search, failure counter reservation, bind, then local second factor or enrollment |
| [`session-lifecycle.puml`](session-lifecycle.puml) | state | Pending second factor, enrollment (invitation or first federated sign-in), recovery, active, recently verified (local or provider step-up), ended |
| [`scorm-export.puml`](scorm-export.puml) | sequence | SCORM 1.2 / 2004 export of one published module as one SCO, with the shared player bundle and the runtimes `Scorm12Runtime` and `Scorm2004Runtime` |

## Rendering

The toolchain in `shell.nix` contains PlantUML and Graphviz. Once the
repository is bootstrapped, `make docs` renders every diagram to
`docs/architecture/out/` (git-ignored). Before that, the same result comes from:

```sh
nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/b25309931cfda5f0b8805f462a29897eeae50168.tar.gz \
  -p plantuml graphviz --run "plantuml -tsvg -o out docs/architecture/*.puml"
```

## Conventions

- Class names in the diagrams match the Ecto schema module names under
  `Espalier.<Context>`. Attribute names match the database columns.
- Associations without a label are `belongs_to` / `has_many` relations.
- A note in a diagram states a rule that the code enforces and a test covers.
