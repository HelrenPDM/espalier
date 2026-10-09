# Identity providers

> Draft of task 0006. Task 0017 finalizes this guide; task 0007 adds the
> LDAP and Active Directory section.

Espalier signs people in through Microsoft Entra ID, Google Workspace and any
standards-compliant OpenID Connect provider. The operator configures each
provider through environment variables, and the sign-in page lists them in the
order of `AUTH_PROVIDERS`. Local accounts (passkey, or password with a second
factor) keep working next to the providers. The security rules behind this
guide are in [`../security/authentication.md`](../security/authentication.md),
section "OIDC sign-in".

## Overview

### Provider types

| Type | Use | Identity key | Roles |
|---|---|---|---|
| `entra` | Microsoft Entra ID, one tenant | issuer, `tid` and `oid` | App Roles in the `roles` claim |
| `google` | Google Workspace, one hosted domain | issuer and `sub` | manual grants only |
| `oidc` | any other OIDC provider | issuer and `sub` | a list of strings in `AUTH_<KEY>_ROLE_CLAIM` |

An account is never found or linked through an e-mail address,
`preferred_username` or `upn`. A verified address from the provider is stored
on the account and refreshed at each sign-in when no other account uses it.

### Variables

`AUTH_PROVIDERS` lists the provider keys (lower case, letters, digits and
underscores), and `<KEY>` is the upper-case form of a key. Every value is
trimmed, and one pair of surrounding double quotes is removed. An invalid
configuration stops the boot with a message that names the variable.

| Variable | Types | Required | Default and rule |
|---|---|---|---|
| `AUTH_<KEY>_TYPE` | all | yes | `entra`, `google` or `oidc` |
| `AUTH_<KEY>_LABEL` | all | yes | text of the button on the sign-in page |
| `AUTH_<KEY>_CLIENT_ID` | all | yes | |
| `AUTH_<KEY>_TENANT_ID` | `entra` | yes | the tenant GUID |
| `AUTH_<KEY>_ISSUER` | all | `oidc` | `entra`: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`, and a set value must end in `/<TENANT_ID>/v2.0`; `google`: `https://accounts.google.com`; outside development the issuer must use `https` |
| `AUTH_<KEY>_CLIENT_CERT_FILE`, `AUTH_<KEY>_CLIENT_KEY_FILE` | `entra`, `oidc` | `entra` in production | PEM files of the client certificate and its RSA key, both or neither |
| `AUTH_<KEY>_CLIENT_KID_FORMAT` | with a certificate | no | `x5t` (default, the only format that Entra ID accepts), `x5t_s256` or `sha1_hex` |
| `AUTH_<KEY>_CLIENT_SECRET` | all | `google`, and `oidc` without certificate | refused for `entra` in production |
| `AUTH_<KEY>_CLIENT_AUTH` | `oidc` | no | `client_secret_basic` (default with a secret), `client_secret_post`, `private_key_jwt` (default with a certificate) |
| `AUTH_<KEY>_HOSTED_DOMAIN` | `google` | yes | compared with the `hd` claim |
| `AUTH_<KEY>_ROLE_CLAIM` | `oidc` | no | `roles` |
| `AUTH_<KEY>_ROLE_MAP` | `entra`, `oidc` | no | `role=value;role=value` with the roles `facilitator`, `author`, `registrar`, `analyst` and `admin`; a role may appear more than once |
| `AUTH_<KEY>_MFA` | all | no | `local` (default) or `idp_trusted` |
| `AUTH_<KEY>_MFA_AMR` | all | no | comma-separated `amr` values that count as multi-factor in `idp_trusted` mode; default `mfa` (RFC 8176, section 2) |
| `AUTH_<KEY>_PROVISION` | all | no | `true` for `entra` and `google`, `false` for `oidc` |
| `AUTH_<KEY>_ALLOWED_HOSTS` | all | no | comma-separated host names of the provider's endpoints; default below |

A variable that a type does not read, such as `AUTH_<KEY>_ROLE_MAP` for
`google`, stops the boot, so a setting never silently has no effect. Client
secrets, certificates and keys come from the runtime environment only;
`.env.example` holds empty placeholders.

### Addresses to register at the provider

| Address | Value |
|---|---|
| Redirect URI, one per provider | `PUBLIC_URL/auth/oidc/<key>/callback` |
| Front-channel logout URL (Entra ID) | `PUBLIC_URL/auth/oidc/<key>/front-channel-logout` |
| Post-logout redirect URI | `PUBLIC_URL/signed-out` |

Each provider has its own redirect URI. A response that arrives at the
redirect URI of another provider ends the sign-in before the code is redeemed.

### MFA modes

| Mode | Second factor | Recorded in the session |
|---|---|---|
| `local` (default) | a local passkey, TOTP code or recovery code after every provider sign-in | methods `oidc` and the local factor |
| `idp_trusted` | the provider's multi-factor sign-in | methods `oidc` and `idp_mfa`, and the provider's `amr` values |

`idp_trusted` is an operator decision for a provider that enforces
multi-factor sign-in itself, such as Entra ID with Conditional Access. The
boot logs a warning for each such provider. The `amr` rule applies:

- An ID token whose `amr` holds a value of `AUTH_<KEY>_MFA_AMR` counts as
  multi-factor.
- An ID token with `amr` but without such a value, for example `["pwd"]`
  after Conditional Access skipped MFA, leads to the local second factor, as
  in `local` mode.
- An ID token without `amr` keeps the operator's statement and counts as
  multi-factor.

### Provisioning and the first sign-in

With `AUTH_<KEY>_PROVISION=true`, the first sign-in of an unknown identity
creates an account with the display name, the verified address when the
provider sends one, and the roles of `AUTH_<KEY>_ROLE_MAP`. A verified address
that already belongs to another account stops the provisioning with
`oidc_no_account`; it never links the identity to that account.

In `local` mode, the first sign-in of an account without a local factor
opens an enrollment session: the person enrolls a passkey or a TOTP factor
and receives recovery codes. Whoever passes the provider's sign-in first for
a new account binds that first factor, so an operator who switches
provisioning on relies on the provider's own sign-in protection for that
step.

### Access when provisioning is off

1. An admin invites the person (local account).
2. The person accepts the invitation and enrolls a passkey, or a password
   with TOTP.
3. Signed in with that account, the person links the provider in the
   security settings. The settings call
   `POST /api/auth/oidc/:provider/intents` with the purpose `link`, which
   needs a second factor from the last 10 minutes, and open the returned URL
   in the same browser. The link works only from the browser session of that
   account, and the account receives the mail `identity_linked`.

### What a link changes

Password sign-in, discoverable passkey sign-in and self-service recovery
serve only accounts without an external identity. After a link, the account
signs in only through the provider, and its passkeys, TOTP factor and
recovery codes serve as second factor after the provider sign-in.

The first version has no route that removes an external identity. An
operator who removes a provider from `AUTH_PROVIDERS` therefore leaves the
accounts that hold an identity of it without a sign-in pathway, and an admin
reset of the factors does not restore one, because it keeps the identity.
Keep a provider configured while accounts hold identities of it.

### Sessions and logout

- A platform session is independent of the provider session. Signing out of
  Espalier ends the platform session, and signing out at the provider ends
  platform sessions only through the two paths below.
- Front-channel logout (Entra ID): the provider loads the front-channel
  logout URL in a hidden frame with the `sid` of its session, and every
  platform session that started from that provider session ends. Entra ID
  sends `sid` without `iss`. The ID
  token must carry `sid`, which Entra ID sends as an optional claim.
- RP-initiated logout: where the provider offers an end-session endpoint
  (Entra ID and many OIDC providers, not Google), signing out of Espalier
  also sends the browser to the provider's logout page, which returns to
  `PUBLIC_URL/signed-out`.
- Back-channel logout is not supported, because neither oidcc 3.9.0 nor
  Entra ID offers it.
- A step-up for a sensitive change in `idp_trusted` mode sends the person
  to the provider again with `max_age=0`, and the provider must report a
  fresh `auth_time` and a multi-factor `amr`. Users of `local` providers
  confirm with their local passkey or TOTP code instead.

### Error codes

The sign-in ends at `/auth/finish?error=<code>` when it fails:

| Code | Causes |
|---|---|
| `oidc_cancelled` | The provider returned `error=access_denied`, for example after "Cancel". |
| `oidc_unavailable` | The provider has not been reached since the start, the provider is unreachable, an endpoint lies outside `AUTH_<KEY>_ALLOWED_HOSTS`, or the provider offers no PKCE method S256. |
| `oidc_no_account` | No identity matches, and provisioning is off or the verified address belongs to another account. |
| `oidc_identity_in_use` | A link names an identity that belongs to another account. |
| `oidc_failed` | Every other failure: state, nonce, PKCE, signature, algorithm, audience, expiry, `iss`, a missing transaction, a response at another provider's redirect URI, tenant, hosted domain, groups overage, missing claims, a stale `auth_time` or a single-factor `amr` at a step-up, a disabled account, a second identity of the same provider, a step-up for another identity, an invalid intent, or an intent opened outside the session that created it. |

The security log records each failure as `authn_login_fail` with the
provider, the purpose and the reason ([`../security/logging.md`](../security/logging.md)).

## Outbound connections

Espalier talks to a provider for discovery
(`<issuer>/.well-known/openid-configuration`), its keys (JWKS) and the token
request; it calls no provider API after the sign-in. Every request follows no
redirect and validates the provider's TLS certificate.

`AUTH_<KEY>_ALLOWED_HOSTS` lists the host names that the endpoints of the
provider's discovery document may use. The default is the host of the
issuer, and for `google` also the hosts of Google's token and JWKS endpoints.
When the authorization, token, JWKS, end-session or pushed authorization
endpoint lies on another host or does not use `https`, every sign-in at
that provider fails with
`oidc_unavailable` before any redirect or token request, so the client secret
or assertion never reaches another host.

The provider worker loads the JWKS before this check can run. Enter the
hosts of the table into the egress allowlist of the container network or the
outbound proxy, which covers that request as well.

| Type | Issuer | Authorization | Token | JWKS | End session |
|---|---|---|---|---|---|
| `entra` | `login.microsoftonline.com` | `login.microsoftonline.com` | `login.microsoftonline.com` | `login.microsoftonline.com` | `login.microsoftonline.com` |
| `google` | `accounts.google.com` | `accounts.google.com` | `oauth2.googleapis.com` | `www.googleapis.com` | none |
| `oidc` | the issuer host | from the provider's discovery document | from the document | from the document | from the document, when offered |

The Entra hosts come from the `organizations` discovery document, and the
Google hosts from `https://accounts.google.com/.well-known/openid-configuration`,
both retrieved 2026-10-09. The Entra spike below checks the document of the
test tenant.

## Microsoft Entra ID

1. Register an application for accounts in this organizational directory
   only (single tenant), with the platform Web and the redirect URI
   `PUBLIC_URL/auth/oidc/<key>/callback`.
2. Create a client certificate and its RSA key, for example
   `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj /CN=espalier -keyout entra.key -out entra.crt`.
   Upload `entra.crt` under Certificates and secrets. Store both files
   outside the image, readable only by the user of the application (mode
   `0400`), and set `AUTH_<KEY>_CLIENT_CERT_FILE` and
   `AUTH_<KEY>_CLIENT_KEY_FILE`. Upload a new certificate before the old one
   expires, switch the files and restart, then remove the old certificate.
   The client signs its assertions with PS256, the algorithm that Microsoft
   documents for certificate credentials, and names the certificate in the
   key id by its `x5t` thumbprint.
3. Use no client secret in production: Espalier refuses
   `AUTH_<KEY>_CLIENT_SECRET` for `entra` outside development.
4. Create App Roles whose values match `AUTH_<KEY>_ROLE_MAP`, for example
   `Espalier.Author` and `Espalier.Admin` with
   `AUTH_ENTRA_ROLE_MAP="author=Espalier.Author;admin=Espalier.Admin"`, and
   assign them to users or groups under Enterprise applications. Each
   sign-in replaces the roles that came from this provider; roles from
   another provider of the same account and roles that an admin granted in
   Espalier stay.
5. Add the optional ID token claims `auth_time`, `amr`, `email` and
   `xms_edov`. `sid` is needed for front-channel logout. An address counts as
   verified only with `xms_edov`.
6. Register `PUBLIC_URL/auth/oidc/<key>/front-channel-logout` as
   front-channel logout URL.
7. For `AUTH_<KEY>_MFA=idp_trusted`, enforce multi-factor sign-in for the
   application with Conditional Access. That policy is the operator's basis
   for the mode.

A groups claim is optional. Limit it to the groups assigned to the
application; a token with a groups overage indicator fails the sign-in.
`department` does not reach the ID token without claims mapping, which
Espalier does not use, so the org unit of Entra users stays empty.

### Spike results (task 0006, step 18, decision D4)

The spike ran on 2026-10-09 against a Microsoft 365 business tenant with
security defaults, a single-tenant app registration, a certificate
credential and two test users.

| Item | Result |
|---|---|
| Key id of the client assertion | Entra ID accepts only `x5t`, the Base64url SHA-1 of the certificate. `x5t_s256` and `sha1_hex` fail with AADSTS700027 ("The certificate with identifier used to sign the client assertion is not registered on application"), so `x5t` is the default. |
| Signing algorithm and audience | Entra ID accepts PS256 and the issuer as `aud`; the token endpoint as `aud` and RS256 work as well. Espalier signs with PS256 and the issuer. |
| Claims of the ID token | `sid`, `roles` and `auth_time` arrive as configured. `amr` never arrived, also not after a sign-in with the Authenticator app. |
| Step-up with `max_age=0` | Entra ID asks for the credentials and the second factor again and returns a fresh `auth_time`. |
| Endpoint hosts | The authorization, token, JWKS and end-session endpoints of the tenant document lie on `login.microsoftonline.com`, the default of `AUTH_<KEY>_ALLOWED_HOSTS`. |
| Front-channel logout | The request carries `sid` only, without `iss`, and ends the sessions of that provider session. |
| Security defaults | A new user must register the Authenticator app at the first sign-in. Later sign-ins asked for no second factor, except the step-up with `max_age=0`, and in `idp_trusted` mode still became sessions with `idp_mfa`, because the ID token carries no `amr`. |

Because Entra ID sends no `amr`, every Entra sign-in in `idp_trusted` mode
rests on an application-scoped Conditional Access policy that enforces
multi-factor sign-in. Security defaults alone are not sufficient evidence:
they require registration and challenge conditionally, but do not ensure MFA
on every application sign-in. With `local` mode, the person confirms each
sign-in with a local passkey or TOTP code.

## Google Workspace

1. Create an OAuth client of the type Web application with the redirect URI
   `PUBLIC_URL/auth/oidc/<key>/callback`.
2. Set `AUTH_<KEY>_CLIENT_SECRET`. Google offers `client_secret_post` and
   `client_secret_basic` only; Espalier uses `client_secret_basic`.
3. Set `AUTH_<KEY>_HOSTED_DOMAIN` to the Workspace domain. The `hd` claim of
   every ID token must equal it; the `hd` request parameter is only a hint
   for Google's account chooser.
4. Google sends no role claim, so roles come from manual grants in Espalier.
5. Signing out of Espalier ends the platform session only, because Google
   offers no end-session endpoint.

Google advertises the RFC 9207 `iss` parameter, and Espalier requires it on
every callback.

## Generic OIDC

- Espalier reads the discovery document at
  `<issuer>/.well-known/openid-configuration`. Its `issuer` must equal
  `AUTH_<KEY>_ISSUER` exactly, and `scopes_supported` must contain `openid`.
- `code_challenge_methods_supported` must contain `S256`; otherwise every
  sign-in fails closed with `oidc_unavailable`.
- ID tokens must be signed with RS256, PS256 or ES256, whatever the document
  lists.
- Client authentication: `client_secret_basic` or `client_secret_post` with
  `AUTH_<KEY>_CLIENT_SECRET`, or `private_key_jwt` with a certificate and
  key. A `private_key_jwt` assertion is signed with PS256 only; a provider
  that accepts no PS256 assertion authenticates the client with a secret.
- The role claim (`AUTH_<KEY>_ROLE_CLAIM`, default `roles`) must be a list of
  strings in the ID token; a distributed claim fails the sign-in.
- Provisioning is off by default, so people get access through an invitation
  and a link.
- Request objects, DPoP and mutual TLS are not used, also when the document
  offers them.

## Development

`make run` and `make dev-oidc` start a mock provider on port 4010 with the
profiles `entra`, `google` and `oidc` and invented users. The development
block of `.env.example` configures all three; set each client secret to the
fixture secret of the mock in `config/dev.exs`, which works only against the
mock. The tests use the same mock on port 4011.
