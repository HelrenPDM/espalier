# Documentation

The guides describe Espalier for the people who adopt, run and fill it. The
four introductions come first and give a reader who meets Espalier for the
first time the shortest path to a working result. The reference guides
follow and hold the detail that the introductions link to. The plan in
[`../plan/README.md`](../plan/README.md) states the decisions behind both,
and [`../architecture/README.md`](../architecture/README.md) shows the
domain model and the sign-in flows as diagrams.

## Introductions

| Guide | Read it to |
|---|---|
| [`purpose.md`](purpose.md) | Learn what Espalier is for, who uses it and which capabilities it has and does not have |
| [`setup.md`](setup.md) | Install it for development, as a demo instance or as a production instance |
| [`tenant-and-authentication.md`](tenant-and-authentication.md) | Understand the instance model, connect an identity provider or a directory and assign roles |
| [`course-yaml.md`](course-yaml.md) | Learn the building blocks of a course: the YAML and Markdown files of a content pack |

## Reference guides

| Guide | Covers |
|---|---|
| [`self-hosting.md`](self-hosting.md) | Image, environment file, PostgreSQL with TLS, reverse proxy, first admin, content, backups and upgrades of a production instance |
| [`operations.md`](operations.md) | Release functions, logs, health, background jobs, sessions and keys of a running instance |
| [`demo-instance.md`](demo-instance.md) | The demo profile, its Makefile targets, the demo banner, test notes and the reset |
| [`identity-providers.md`](identity-providers.md) | Microsoft Entra ID, Google Workspace, generic OIDC, Active Directory and generic LDAP |
| [`security.md`](security.md) | Verification target, secrets, keys, sessions, TLS, outgoing connections, limits and the dependency policy |
| [`content-packs.md`](content-packs.md) | Every file, field, block kind and check of the content pack format |
| [`pack-workbench.md`](pack-workbench.md) | Editing a content pack in the admin area |
| [`scorm-export.md`](scorm-export.md) | SCORM 1.2 and 2004 export of a module and the export of a program as a content pack |
