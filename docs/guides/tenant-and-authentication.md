# Instance, tenant and authentication

This chapter explains how an Espalier instance relates to an organization,
what "tenant" means when an identity provider is involved, which ways of
signing in exist, and how an operator configures them, with two worked
configurations. It continues with the roles, the first admin, the session
settings and the demo accounts. [`purpose.md`](purpose.md) comes before the
setup, [`setup.md`](setup.md) comes before this chapter and
[`course-yaml.md`](course-yaml.md) after it. The variables of every provider
type are in [`identity-providers.md`](identity-providers.md), the security
rules behind them in
[`../security/authentication.md`](../security/authentication.md), the security
settings of the whole instance in [`security.md`](security.md), the logs of a
running instance in [`operations.md`](operations.md) and the sign-in flows as
diagrams in [`../architecture/README.md`](../architecture/README.md).

## The instance model

One organization runs one instance. Multi-tenancy is out of scope for the
first version (plan section 1, [`../plan/README.md`](../plan/README.md)), and
the verification matrix records ASVS 8.4.1 (cross-tenant controls) as not
applicable for this reason ([`../security/asvs-l2.md`](../security/asvs-l2.md),
row 8.4.1). No table separates the records of several organizations. The only
tenant column, `external_identities.tenant_id`, holds the Entra ID tenant of
an identity.

### Several organizations

A provider that serves several organizations runs one instance per
organization. The instances share nothing at runtime:

| Per instance | Setting | Reason |
|---|---|---|
| Host name | `PHX_HOST`, `PUBLIC_URL` | A production boot stops unless `PUBLIC_URL` names `PHX_HOST` ([`self-hosting.md`](self-hosting.md), section "Host name"). Passkeys belong to this host name. |
| Database | `DATABASE_URL` | Accounts, records and role grants live in it. |
| Keys | `SECRET_KEY_BASE`, `CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET` | The Cloak keys encrypt the personal columns, and `CLOAK_HMAC_SECRET` keys the stored hash of every external identity ([`../security/key-management.md`](../security/key-management.md)). |
| Export volume | Compose volume `exports` | `compose.yaml` fixes `EXPORT_DIR` to `/data/exports`, and the volume of each Compose project holds the packages of that instance. |
| Identity providers | `AUTH_PROVIDERS` and `AUTH_<KEY>_*` | Each organization connects its own tenant or directory. |

Two instances on one host need separate Docker Compose project names,
environment files and published ports (`APP_PORT`), and with the proxy example
also `HTTPS_PORT`, `PROXY_SUBNET` and `PROXY_ADDRESS` (Compose variables,
not application settings)
([`demo-instance.md`](demo-instance.md), section "Serving the demo").

### Groups inside one instance

An organization that wants to tell departments apart inside one instance has
these mechanisms:

- **Roles** apply to the whole instance. A role grant holds user, role,
  source and provider key, and has no group or org-unit scope. The role maps
  of the providers decide who holds `author`, `analyst` or `admin`.
- **The org unit** is a text attribute of the user, stored encrypted. Only a
  directory provider fills it: `AUTH_<KEY>_ORG_UNIT_ATTR` names the LDAP
  attribute (for example `department`), and each directory sign-in refreshes
  it. The OIDC types leave it empty, Entra ID included.
- **`INSIGHTS_ORG_UNIT`** (default `false`) decides whether the anonymous item
  statistics and the competence reports keep the org unit. With the default,
  reports break down by program and month only.
- **`INSIGHTS_MIN_GROUP_SIZE`** (default 5) suppresses every report cell with
  fewer responses or people (plan section 10).
- **`REGISTRAR_ENABLED`** (default `false`) switches on the per-person
  credential list of the role `registrar`, which shows the org unit.

## The word "tenant" in the identity context

Espalier has no tenants of its own. The word appears for Microsoft Entra ID,
and a comparable boundary exists at the other providers:

| Type | Boundary | Setting | Check at each sign-in |
|---|---|---|---|
| `entra` | One Entra ID tenant | `AUTH_<KEY>_TENANT_ID`, a GUID, stored in lower case | The `tid` claim must equal it. Otherwise the sign-in fails with `oidc_failed`, and the security log records the reason `tenant_mismatch`. |
| `google` | One Workspace domain | `AUTH_<KEY>_HOSTED_DOMAIN` | The `hd` claim must equal it (lower case). Otherwise the sign-in fails with `oidc_failed` and the reason `domain_mismatch`. |
| `oidc` | The issuer | `AUTH_<KEY>_ISSUER` | The issuer of the discovery document must equal it. |
| `ldap` | One directory domain per provider key | `AUTH_<KEY>_HOST`, `AUTH_<KEY>_BASE_DN` | The search starts at the base DN, and a bind with the returned DN proves the password. |

The troubleshooting table of [`identity-providers.md`](identity-providers.md)
lists these reasons. For `entra`, the default issuer is
`https://login.microsoftonline.com/<TENANT_ID>/v2.0`, and a configured issuer
must end in `/<TENANT_ID>/v2.0`. The app registration at Microsoft is
single-tenant. The `oid` claim must be present, and a groups overage
indicator in the token fails the sign-in.

### How the tenant becomes part of the identity key

`Espalier.Accounts.ExternalIdentity.hash_input/3` joins issuer, tenant id (an
empty string when there is none) and subject with NUL bytes, and the column
`subject_hash` stores the keyed hash of that value (HMAC-SHA256 under
`CLOAK_HMAC_SECRET`). An identity is unique per provider key and
`subject_hash`, and a user holds at most one identity per provider key.

| Type | Issuer | Tenant id | Subject |
|---|---|---|---|
| `entra` | `https://login.microsoftonline.com/<tid>/v2.0` | `tid` | `oid` |
| `google` | `https://accounts.google.com` | none | `sub` |
| `oidc` | `AUTH_<KEY>_ISSUER` | none | `sub` |
| `ldap` | `ldap:<key>` | none | `objectGUID` as UUID (`ad`) or `entryUUID` (`generic`) |

The hosted domain of Google is checked but not part of the key. An account is
never found or linked through an e-mail address, `preferred_username`, `upn`,
`userPrincipalName` or `sAMAccountName` (plan section 6.2, rule 3). A verified
address is stored on the account and refreshed at each sign-in when no other
account uses it.

## Sign-in pathways

Every pathway ends in the same function, which creates a server-side session
and records the methods used. Each session has a strength, and a password
alone never opens one. Plan section 6.2 states the pathways, and
[`../security/authentication.md`](../security/authentication.md), section
"Pathways and session strength", lists the routes.

| Pathway | First step | Second factor | Session strength |
|---|---|---|---|
| Passkey (local accounts) | WebAuthn discoverable credential with user verification | Included in the user verification | `mfa` |
| Password (local accounts) | Password, checked with Argon2id | TOTP code, passkey or recovery code | `mfa` |
| Invitation | Single-use e-mail link, valid 10 minutes | The person enrolls a passkey, or a password with TOTP | `enrollment` until a factor exists, then `mfa` |
| Recovery (local accounts) | A saved recovery code and an e-mail link | None; the session only permits re-enrollment | `recovery` (30 minutes), then `mfa` |
| OIDC (`entra`, `google`, `oidc`) | The provider's sign-in | `local`: passkey, TOTP code or recovery code of the local account. `idp_trusted`: the provider's multi-factor sign-in. | `mfa`; `enrollment` at the first sign-in without a local factor |
| LDAP or Active Directory | Bind with the directory password | Passkey, TOTP code or recovery code (`local` is the only mode) | `mfa`; `enrollment` at the first sign-in without a local factor |
| Demo | Choice of a pseudonymous test person | None | `demo` |

Three rules hold for all pathways:

1. An e-mail link never opens a full session. An `enrollment` or `recovery`
   session reaches the enrollment routes alone, for 30 minutes, and a local
   account cannot exist without a second factor.
2. Passkey sign-in, password sign-in and recovery serve accounts without an
   external identity. After an account links a provider or a directory, it
   signs in only through that provider, and its passkey, TOTP factor and
   recovery codes serve as the second factor.
3. Sensitive account changes (password, e-mail address, factors, ending a
   session) and every change under `/api/admin` need a second factor from the
   last 10 minutes.

## Local accounts

Local accounts are on by default (`LOCAL_ACCOUNTS=true`). They start from an
invitation mail, so such an instance needs SMTP
([`self-hosting.md`](self-hosting.md), section "Mail"). A password has 15 to
128 code points and must not be a common password or a word of
`PASSWORD_CONTEXT_WORDS` (comma-separated words of the organization).
`PASSWORD_BREACH_CHECK=hibp` adds a query to the Pwned Passwords range API and
is off by default. A person who has lost every second factor and holds no
unused recovery code has no self-service pathway: an admin resets the factors
after the organization verified the identity
([`../security/authentication.md`](../security/authentication.md), section
"Reset of second factors (decision D11)").

`SIGNUP` decides how a local account comes into being:

| Value | Behavior |
|---|---|
| `closed` (default) | Admins invite people. `POST /api/auth/invitations` answers 404. |
| `invite` | Additionally, an invited person who has not enrolled yet can request a new link. An unknown address receives nothing. |
| `domain` | Additionally, an unknown address whose domain equals an entry of `SIGNUP_DOMAINS` (required with this value, comma-separated) receives an invitation mail, and the account is created with it. |

The request answers 202 with the same body for every address, so it reveals
no account.

```sh
LOCAL_ACCOUNTS=true
SIGNUP=domain
SIGNUP_DOMAINS=example.org
```

`LOCAL_ACCOUNTS=false` answers 404 on passkey sign-in, password sign-in,
invitations, recovery and the admin invitation route, and the bootstrap
skips unknown addresses. The boot then requires another pathway: a provider
in `AUTH_PROVIDERS`, or `AUTH_DEMO=true`.

## External providers

`AUTH_PROVIDERS` lists the provider keys in the order of the sign-in page. A
key starts with a lower-case letter, continues with lower-case letters,
digits or underscores and has at most 32 characters; `<KEY>` is its upper-case
form. Each provider needs `AUTH_<KEY>_TYPE` (`entra`, `google`, `oidc` or
`ldap`) and `AUTH_<KEY>_LABEL`, the text of the sign-in button. An invalid
value stops the boot with a message that names the variable. An OIDC type also
refuses the variables of another type (for example `AUTH_<KEY>_HOSTED_DOMAIN`
on `entra`), whereas an `ldap` provider ignores variables it does not read.

| Setting | Types | Default | Meaning |
|---|---|---|---|
| `AUTH_<KEY>_MFA` | all | `local` | `local`: a local passkey, TOTP code or recovery code after each provider sign-in. `idp_trusted`: the provider's multi-factor sign-in counts. LDAP accepts `local` only. |
| `AUTH_<KEY>_MFA_AMR` | OIDC types | `mfa` | The `amr` values that count as multi-factor in `idp_trusted` mode. |
| `AUTH_<KEY>_PROVISION` | OIDC types | `true` for `entra` and `google`, `false` for `oidc` | Whether the first sign-in of an unknown identity creates the account. An LDAP provider always provisions. In both cases, an identity whose verified address belongs to another account is refused and has to be linked from a signed-in session of that account. |
| `AUTH_<KEY>_ROLE_MAP` | `entra`, `oidc`, `ldap` | empty | Maps claim values or group DNs to roles. |

`idp_trusted` is an operator decision for a provider that enforces
multi-factor sign-in itself, and the boot logs a warning for each such
provider. Entra ID sent no `amr` claim in the tested tenant, so the mode there
rests on a Conditional Access policy for the application
([`identity-providers.md`](identity-providers.md), section "Spike results").
With provisioning off, an admin invites the person as a local account, and the
person links the provider in the security settings. No route removes an
external identity, so a provider stays in `AUTH_PROVIDERS` while accounts hold
an identity of it; removing it leaves those accounts without a sign-in pathway
([`identity-providers.md`](identity-providers.md), section "What a link
changes").

A role map has the form `role=value;role=value`, split at the first `=` of
each pair. The roles are `facilitator`, `author`, `registrar`, `analyst` and
`admin`; `learner` cannot be mapped. The value is an App Role (`entra`), an
entry of the claim in `AUTH_<KEY>_ROLE_CLAIM` (`oidc`, default `roles`) or a
group DN (`ldap`). Google sends no role claim, so its roles come from manual
grants. Each sign-in replaces the roles that came from that provider (source
`idp_claim`). Roles that an admin or the operator granted (source `manual`)
and roles from another provider of the same account stay.

For the OIDC types, register the redirect URI `PUBLIC_URL/auth/oidc/<key>/callback`
at the provider, and for Entra ID the front-channel logout URL. `PUBLIC_URL`
stands for the form that Espalier sends, with a lower-case host, no default
port and no trailing slash, and the provider compares addresses exactly
([`identity-providers.md`](identity-providers.md), section "Addresses to
register at the provider").

For `PUBLIC_URL=https://espalier.example.org` and the key `entra`, the
redirect URI is `https://espalier.example.org/auth/oidc/entra/callback`. A
directory needs no address at the provider, because the browser posts the
credentials to Espalier at `POST /api/auth/ldap/<key>`.

### Example: Microsoft Entra ID

Register an application for accounts in this organizational directory only,
with the redirect URI and the front-channel logout URL above. Upload a client
certificate under "Certificates and secrets" and keep the certificate and RSA
key outside the image (outside development, the certificate is required and a
client secret is refused). Create App Roles whose values match the role map,
and add the optional ID token claims that
[`identity-providers.md`](identity-providers.md), section "Microsoft Entra ID",
lists. Then set the variables and mount the files into the container
([`self-hosting.md`](self-hosting.md), section "Identity providers and
certificate files"):

```sh
AUTH_PROVIDERS=entra
AUTH_ENTRA_TYPE=entra
AUTH_ENTRA_LABEL="Microsoft 365"
# The directory (tenant) ID and the application (client) ID, both GUIDs.
AUTH_ENTRA_TENANT_ID=
AUTH_ENTRA_CLIENT_ID=
AUTH_ENTRA_CLIENT_CERT_FILE=/etc/espalier/secrets/entra.crt
AUTH_ENTRA_CLIENT_KEY_FILE=/etc/espalier/secrets/entra.key
AUTH_ENTRA_ROLE_MAP="author=Espalier.Author;admin=Espalier.Admin"
AUTH_ENTRA_MFA=local
AUTH_ENTRA_PROVISION=true
```

After a restart, the line `Effective settings: ...` ends with
`providers: entra (entra, MFA local)`, and the sign-in page offers the button
"Microsoft 365". Each person enrolls a passkey or a TOTP factor at the first
sign-in.

### Example: Active Directory

Create a dedicated service account that reads user objects below the base DN
and holds no write rights, and export the CA chain of the domain controller as
a PEM file. `AUTH_<KEY>_HOST` must be a DNS name that the certificate names (an
IP address is refused). Read the lockout threshold and the counter reset time
of the domain, and set `AUTH_<KEY>_FAILURE_LIMIT` (required, 1 to 49) below the
threshold and `AUTH_<KEY>_LOCK_MINUTES` (default 30) to at least the reset
time ([`identity-providers.md`](identity-providers.md), section "Active
Directory"):

```sh
AUTH_PROVIDERS=ldap
AUTH_LDAP_TYPE=ldap
AUTH_LDAP_LABEL="Company account"
AUTH_LDAP_HOST=dc1.example.org
AUTH_LDAP_TLS=ldaps
AUTH_LDAP_CA_CERT_FILE=/etc/espalier/secrets/directory-ca.pem
AUTH_LDAP_BIND_DN="CN=svc-espalier,OU=Service Accounts,DC=example,DC=org"
# The password of the service account, from the secrets store of the operator.
AUTH_LDAP_BIND_PASSWORD=
AUTH_LDAP_BASE_DN=DC=example,DC=org
AUTH_LDAP_DIRECTORY=ad
AUTH_LDAP_ORG_UNIT_ATTR=department
AUTH_LDAP_ROLE_MAP="author=CN=Espalier Authors,OU=Groups,DC=example,DC=org;admin=CN=Espalier Admins,OU=Groups,DC=example,DC=org"
AUTH_LDAP_FAILURE_LIMIT=4
AUTH_LDAP_LOCK_MINUTES=30
```

Check the setup before the first sign-in:

```sh
docker compose exec app bin/espalier eval 'Espalier.Release.check_ldap("ldap")'
```

The call prints one line per step (TLS handshake, connection, service bind
and a search at the base DN) without a password or directory data. The `ad`
profile searches `sAMAccountName` and `userPrincipalName` and keys the account
on `objectGUID`, so a rename in the directory keeps the account. Espalier has
no setting that restricts the sign-in to a group: every enabled person entry
below the base DN that the search finds (for `ad` the object category `person` and the object class `user`, for
`generic` the object class `person`) can sign in as a learner, disabled Active Directory accounts are
refused, and the role map adds roles.

Google Workspace and any other OIDC provider follow the pattern of the Entra ID
example with their own variables
([`identity-providers.md`](identity-providers.md)).

## Roles and the first admin

The roles are `learner`, `facilitator`, `author`, `registrar`, `analyst` and
`admin`. Every signed-in user holds `learner` without a stored grant, and the
other roles come from grants. [`purpose.md`](purpose.md), section "Who uses
it", describes what each role does. `registrar` works only with
`REGISTRAR_ENABLED=true`.

A change of the grants of a user ends the sessions of that user. Demo users
hold `learner` only.

No account exists after the installation. The first admin comes from one of
three sources:

1. `BOOTSTRAP_ADMIN_EMAILS` (comma-separated addresses). At every boot, an
   unknown address becomes a local user with the grant `admin` and an
   invitation, and a known active local account without an external identity
   receives the grant when it lacks it. An account with an external identity
   or a disabled account receives nothing and the boot logs a warning, so a
   claim from a provider never grants `admin` through this variable. This
   path needs local accounts and SMTP.
2. The release function, an explicit operator action that also serves a
   federated account:

   ```sh
   docker compose exec app \
     bin/espalier eval 'Espalier.Release.grant_role("admin", "admin@example.org")'
   ```

3. An `admin=` entry in the role map of a provider.

`ADMIN_REQUIRE_PASSKEY` is `true` by default. An admin without a passkey
receives 403 `passkey_required` on every admin route, whatever the MFA mode
of the provider, and enrolls a passkey on the page `/account/security`. With
`false`, the boot logs a warning and admins without a passkey reach the admin
routes. [`self-hosting.md`](self-hosting.md), section "The first admin", walks
through the steps.

## Sessions

Sessions are rows in the database, and the server checks both limits on every
request. The defaults are an inactivity timeout of 60 minutes
(`SESSION_IDLE_MINUTES`), an absolute lifetime of 24 hours
(`SESSION_MAX_HOURS`, a larger value logs a warning at boot, plan section 15,
D9) and 5 concurrent sessions per user (`SESSION_MAX_CONCURRENT`, a new
sign-in ends the oldest session). [`security.md`](security.md), section
"Sessions and cookies", holds the table.

Enrollment and recovery sessions (30 minutes), e-mail links (10 minutes) and
the pending second-factor state (5 minutes) have fixed lifetimes. A password
change, a disabled account and an admin reset of the factors end the
sessions of the user. Signing out of Espalier ends the platform session; the
provider session ends too only through front-channel or RP-initiated logout
([`identity-providers.md`](identity-providers.md), section "Sessions and
logout").

## Demo accounts

`AUTH_DEMO=true` (default `false`) adds the demo sign-in. The sign-in page
lists the buttons "Test person 1" to "Test person 20" in the English interface
("Testperson" in German), and each button posts
its slot (1 to 20) to `POST /api/auth/demo`. A slot is one pseudonymous user
without an e-mail address who keeps the id and the records across sign-ins
and restarts. Demo sessions have the strength `demo`, hold `learner` only and
reach no admin page. Every page shows a banner, the boot logs a warning, and
one client address may sign in ten times per minute. With `AUTH_DEMO=false`,
the route answers 404.

The demo profile ([`demo-instance.md`](demo-instance.md), plan section 15,
D5) combines `AUTH_DEMO=true`, `LOCAL_ACCOUNTS=false`, an empty
`AUTH_PROVIDERS` and `TRACKING_DETAIL=minimal`. `make demo-env` writes
`.env.demo` with generated secrets, and `make demo-up` starts the instance and seeds the demo pack
([`demo-instance.md`](demo-instance.md)).
