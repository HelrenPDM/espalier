# Spike: `wax_` on the target toolchain

Task 0005 step 1 checks whether `wax_` 0.7.0 registers and verifies passkeys
on the toolchain of the project before any passkey code is written. The
spike ran on 2026-10-09 with the scripts `tmp/passkey-spike/spike.exs` and
`tmp/passkey-spike/roundtrip.mjs` (not tracked; `tmp/` is ignored).

**Verdict: GO.**

## Toolchain

```
$ nix-shell --run "elixir --version"
Erlang/OTP 28 [erts-16.4.0.6] [source] [64-bit] [smp:16:16] [ds:16:16:10] [async-threads:1] [jit:ns]

Elixir 1.20.4 (compiled with Erlang/OTP 28)

$ nix-shell --run 'cat "$(elixir -e "IO.write(:code.root_dir())")/releases/28/OTP_VERSION"'
28.5.0.7
```

Browser: Chromium 147.0.7727.15 (revision 1217) from `playwright-driver` of
the pinned nixpkgs, driven by `playwright-core` 1.59.1 through the Chromium
DevTools `WebAuthn` domain.

## Locked versions

```
$ grep -E '"(wax_|x509|cbor|asn1_compiler)"' mix.lock
"asn1_compiler": {:hex, :asn1_compiler, "0.1.1", ...}
"cbor": {:hex, :cbor, "1.0.2", ...}
"wax_": {:hex, :wax_, "0.7.0", ...}
"x509": {:hex, :x509, "0.9.2", ...}
```

## Compile warnings of the dependencies

`mix deps.compile wax_ x509 cbor asn1_compiler --force` printed 13 warnings,
all inside the dependencies. `mix compile --warnings-as-errors` of the
project exited 0.

| Dependency | Location | Warning |
|---|---|---|
| asn1_compiler | `mix.exs` | `xref: [exclude: ...]` is deprecated |
| asn1_compiler | `lib/mix/tasks/compile.asn1.ex:74` | `:asn1ct.compile/2` is undefined |
| cbor | `lib/cbor/decoder.ex:53`, `:63`, `:150`, `:155` | a variable inside `size(...)` needs the pin operator |
| x509 | `lib/x509/certificate.ex:371` | a variable inside `size(...)` needs the pin operator |
| wax_ | `lib/wax/utils/jws.ex:79` (twice), `lib/wax/cose_key.ex:114`, `:115`, `lib/wax/attestation_statement_format/tpm.ex:189` | a variable inside `size(...)` needs the pin operator |
| wax_ | `lib/wax/attestation_statement_format/apple_anonymous.ex:2` | unused `require Logger` |

## Audit

```
$ nix-shell --run "mix hex.audit; mix deps.audit"
Ignored advisories:
  cloak_ecto 1.3.0 - EEF-CVE-2026-94206 (MEDIUM)
  cloak 1.1.4 - EEF-CVE-2026-95105 (HIGH)
No vulnerabilities found.
```

The two ignored advisories are those of task 0003 (`mix.exs`). No advisory
names `wax_`, `x509`, `cbor` or `asn1_compiler`.

## Runs

The spike ran twice with the options of step 6 (no `excludeCredentials`, no
`allowCredentials`, a 64-byte random user handle, `residentKey` and
`userVerification` `"required"`, attestation `"none"`):

1. With `pubKeyCredParams` in the order of step 6 (-8, -7, -257), the virtual
   authenticator of Chromium 147 created an EdDSA credential (COSE algorithm
   -8). `Wax.register/3` accepted it with the UV flag set, and
   `Wax.authenticate/6` verified two assertions. Criterion (b) names the
   algorithm -7 and therefore failed in this run, which printed NO-GO.
2. With `SPIKE_ALGS=es256`, which offers -7 alone, the authenticator created
   an ES256 credential. Every criterion held, and the run recorded the
   payloads in `test/fixtures/webauthn/chromium_cdp_es256.json`.

Criterion (b) assumes that the authenticator picks ES256 from the list of
step 6. Chromium 147 picks the first algorithm it supports, and its virtual
authenticator supports EdDSA. The first run therefore shows that `wax_`
verifies EdDSA as well; the verdict rests on the second run.

In both runs the third `navigator.credentials.get` with
`userVerification: "required"` returned an assertion after
`WebAuthn.setResponseOverrideBits` with `isBadUV: true`, so the fallback with
`"discouraged"` browser options was not needed.

## Criteria (second run)

| Criterion | Result |
|---|---|
| (a) dependencies resolve as listed, `mix compile --warnings-as-errors` exits 0 | holds (versions and warnings above) |
| (b) `Wax.register/3` returns `{:ok, {auth_data, _}}`, `flag_user_verified` is `true`, `credential_public_key[3]` is -7 | holds: `flag_user_verified=true`, `credential_public_key[3]=-7` |
| (c) `Wax.authenticate/6` with the challenge rebuilt from the stored bytes returns `{:ok, auth_data}`, and the `userHandle` equals the registered handle | holds |
| (d) the assertion with the UV bit cleared returns `{:error, %Wax.InvalidClientDataError{reason: :user_not_verified}}` | holds |
| (e) a challenge built with the options has `timeout` 300 and `user_verification` `"required"` | holds |
| (f) no advisory for `wax_`, `x509`, `cbor` or `asn1_compiler` | holds |

## Verdict

GO: `wax_` 0.7.0 with x509 0.9.2 registers and verifies discoverable
passkeys with required user verification on Elixir 1.20.4 and OTP 28.5.0.7.

## Note on the commands

`npm --prefix tmp/passkey-spike init -y` (step 1.4) ignores `--prefix` and
writes `package.json` into the current directory, the repository root. The
following `npm --prefix tmp/passkey-spike install` creates its own
`package.json` in `tmp/passkey-spike/`, so the repository root needs none. A
rerun of the spike runs `npm init -y` inside `tmp/passkey-spike/`.
