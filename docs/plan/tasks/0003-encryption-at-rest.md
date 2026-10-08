# 0003: Encryption at rest with Cloak

> Milestone: M1 Accounts, Depends on: 0001

## Context to read first
- `docs/plan/README.md`, sections 2 (principles 7 and 8), 6.1 (baseline and ASVS matrix), 6.3 (library table), 6.6 (recovery codes under a key derived from `CLOAK_HMAC_SECRET`), 6.9 (encryption at rest), 6.11 (`CLOAK_KEY_V1`, `CLOAK_HMAC_SECRET`), 6.12 (the interfaces this task owns), 13 (Hex 2.5.1) and 16 (risk row on `cloak`).
- `docs/architecture/domain-records.puml`, package "Accounts and authentication": the attributes typed `encrypted` and `hmac` are columns that the Ecto types and the function `Espalier.Hashed.HMAC.hash/1` of this task protect; README section 6.9 and step 16 give the full list. `docs/architecture/context.puml`, component Vault.
- After `mix deps.get`: `deps/cloak/lib/cloak/vault.ex`, `deps/cloak/lib/cloak/ciphers/aes_gcm.ex`, `deps/cloak_ecto/lib/cloak_ecto/type.ex`, `deps/cloak_ecto/lib/cloak_ecto/types/hmac.ex`, and the cloak_ecto 1.3.0 guides `install`, `rotate_keys` and `closure_wrapping` on hexdocs.
- OWASP ASVS 5.0.0 at tag `v5.0.0_release`: chapter V11 Cryptography and the requirements of V13, V14 and V16 that the section "Security requirements" lists.
- Read `docs/plan/tasks/0004-accounts-sessions.md`, steps 10 to 12 (encrypted and hashed columns), 20 and 27 (encrypted job arguments) and 42 (layout of `docs/security/asvs-l2.md` and the ownership table of its rows).

## Goal
Personal data and authenticator secrets can be stored in PostgreSQL as
AES-256-GCM ciphertext, and their lookup values as HMAC-SHA256, through Ecto
types that tasks 0004 to 0007 put on their columns. A tampered value or a wrong
key makes the read raise. Keys come from the environment and are checked at
boot. A release function re-encrypts every row under a new key, production
query logs carry no plaintext, and two documents in `docs/security/` record
every protected field, every key and the rotation runbook. This task also creates
the ASVS matrix `docs/security/asvs-l2.md`, which every security task extends.
The `users` table is created in 0004, so this task proves the types against a
test-only table, and 0004 applies them to `users`.

## Scope
- In: This task pins `cloak` and `cloak_ecto` exactly and records the advisory acknowledgement in `mix.exs`. It adds `Espalier.Crypto.StrictAESGCM`, `Espalier.Vault`, key decoding with boot checks, and the types `Espalier.Encrypted.Binary`, `Espalier.Encrypted.Map`, `Espalier.Encrypted.ClosureBinary` and `Espalier.Hashed.HMAC` with its function `hash/1`. It adds schema rules with tests, a test-only schema on a temporary table, Repo logging and a telemetry handler for production, the release environment that switches off crash dump files and the Erlang distribution, and `Espalier.Crypto.Rotation` with the release functions `rotate_encryption/0` and `encryption_status/0`. It adds `make gen-keys`, the entries in `.env.example`, the project rules in `AGENTS.md`, `docs/security/crypto-inventory.md` and `docs/security/key-management.md`, and it creates `docs/security/asvs-l2.md` in the layout of 0004 with the rows of the requirements below.
- Out: The tables `users`, `users_tokens` and `external_identities` with their encrypted and hashed columns, their rotation-only schemas, `normalize_email/1` and `Espalier.Accounts.ExternalIdentity.hash_input/3` belong to 0004. TOTP factors and recovery codes belong to 0005, the columns `link_identity` and `binding_hash` of `users_tokens` belong to 0006, and the LDAP columns of external identities and failure counters belong to 0007. Each of these tasks writes its rotation-only schemas and completes its inventory rows. The ownership table of the ASVS matrix belongs to 0004 step 42. A rotation procedure for the HMAC secret is outside this task. The fallback type on `:crypto` is built only when a trigger of the fallback plan fires. The ASVS V15 rows on third-party components belong to 0017.

## Security requirements
This list holds exactly the rows whose `Task` column names this task, as the ownership table of 0004 step 42 assigns them (README section 15, decision D16). This task owns each of them. The parentheses name the tasks that extend a row, and the `Notes` of each row state what they add.

- 11.1.1 (extended by 0017): `docs/security/key-management.md` documents the key lifecycle from generation through storage, boot checks and rotation to retirement and loss.
- 11.1.2 (extended by 0017): `docs/security/crypto-inventory.md` lists every key, algorithm and protected column, and a test fails when an encrypted or hashed schema field is missing from it.
- 11.2.1: Encryption and MACs run in OTP `:crypto` through Cloak; the platform implements no primitive of its own.
- 11.2.2: Versioned cipher tags, a key list read at runtime and the rotation function replace a key or a cipher without a schema change.
- 11.2.3: AES-256-GCM and HMAC-SHA256 run with 256-bit keys.
- 11.3.1: The vault encrypts only with AES-256-GCM through the strict wrapper, so no ECB mode and no padding scheme is in use, and a test fails on any other cipher.
- 11.3.2: The vault holds only `Espalier.Crypto.StrictAESGCM` ciphers, and a test fails on any other cipher.
- 11.3.3: Every encrypted column uses authenticated encryption, and a tampered value or a wrong key makes the read raise.
- 11.4.1 (extended by 0004 and 0005; deviation, README section 15, decision D14): `Espalier.Hashed.HMAC` fixes the hash function to SHA-256 whatever the configuration says. 0004 uses SHA-1 for the range request and 0005 HMAC-SHA-1 for TOTP, and the section "Deviations" of the matrix gives the reasons.
- 11.4.3 (extended by 0006 and 0013): Keyed hashes use HMAC-SHA256, whose output has 256 bits.
- 11.5.1 (extended by 0004 and 0005): Keys are 32 bytes from a cryptographically secure generator.
- 11.6.1 (extended by 0005, 0006 and 0017; deviation, README section 15, decision D13): The Cloak keys come from `:crypto.strong_rand_bytes/1`. 0005 and 0006 accept RS256 for the verification of passkey assertions and ID tokens, and the section "Deviations" of the matrix gives the reasons.
- 13.3.1 (extended by 0006, 0007, 0013 and 0017): Keys come from the environment that the operator's secret store fills; the repository holds placeholders and invented development and test keys only.
- 13.3.2: The key management document limits key access to the people who deploy the application and keeps keys out of database backups.
- 14.1.1: The inventory classifies account and authentication data into protection levels. Other data classes follow in the data protection workstream (README section 10).
- 14.1.2: Each protection level in the inventory has documented requirements for storage, lookup, logging and rotation.
- 14.2.4: The encryption, redaction and logging controls work as the inventory defines them, and a test covers each one.
- 16.2.5 (extended by 0004, 0005, 0006, 0007 and 0013): Production query logs and telemetry handlers carry no plaintext of an encrypted or hashed field.
- 16.5.3 (extended by 0006 and 0007): A failed decryption raises, so no code path loads a tampered value as data.

## Steps
1. Check the Hex version: `nix-shell --run "mix hex.info"` must print `Hex: 2.5.1` or later. Otherwise run `nix-shell --run "mix local.hex --force"` and check again. Hex honors `ignore_advisories` only from 2.5.1. Once 0002 is done, `scripts/check-hex-version.sh` runs the same check in `make check`.
2. Add the dependencies to `deps/0` in `mix.exs` with exact versions:
   ```elixir
   {:cloak, "1.1.4"},
   {:cloak_ecto, "1.3.0"},
   ```
   Add `ignore_advisories` to the `hex:` list in `project/0`. When 0002 has run, the list already holds `cooldown: "7d"`. Otherwise create the list, and 0002 adds its key to it.
   ```elixir
   hex: [
     # cloak 1.1.4 and cloak_ecto 1.3.0 have no release that fixes these advisories.
     # EEF-CVE-2026-95105 concerns Cloak.Ciphers.AES.CTR and
     # Cloak.Ciphers.Deprecated.AES.CTR. EEF-CVE-2026-94206 concerns
     # Cloak.Ecto.PBKDF2. Espalier uses neither module: the vault holds only
     # Espalier.Crypto.StrictAESGCM over Cloak.Ciphers.AES.GCM, and lookups use
     # Cloak.Ecto.HMAC. test/espalier/crypto/cipher_allowlist_test.exs fails if
     # that changes. Review rules: docs/security/key-management.md.
     ignore_advisories: ["EEF-CVE-2026-95105", "EEF-CVE-2026-94206"]
   ]
   ```
   Run `nix-shell --run "mix deps.get"`; its output contains no `VULNERABLE!` line. Run `nix-shell --run "mix hex.audit"`; it exits 0 and lists both IDs under `Ignored advisories:`. If 0002 has added `mix_audit`, run `nix-shell --run "mix deps.audit"` as well. If it reports either advisory, ignore that advisory with the option that `mix help deps.audit` documents, and repeat the reason as a comment next to it.
3. Write `Espalier.Crypto.Keys` in `lib/espalier/crypto/keys.ex`, and the exceptions `Espalier.Crypto.InvalidKeyError` and `Espalier.Crypto.DecryptError` (both `defexception [:message]`, the second with the default message `"decryption failed"`) in `lib/espalier/crypto/errors.ex`:
   - `decode!(name, value)` trims `value`, decodes it with `Base.decode64/1` (padding required) and returns the binary when it is exactly 32 bytes. For `nil`, `""`, invalid Base64 or another length it raises `InvalidKeyError` with the message `"#{name} must be 32 random bytes, Base64-encoded"`. No message, log line or exception field contains the value.
   - `cipher_keys!(entries)` takes `[{version, base64}]`, requires at least one entry and distinct positive integer versions, decodes each entry under the name `CLOAK_KEY_V<version>`, requires the decoded keys to be pairwise distinct, and returns `[{version, key}]` sorted by version, highest first.
   - `check!/0` reads `:keys` from `Application.fetch_env!(:espalier, Espalier.Vault)` and `:secret` from `Application.fetch_env!(:espalier, Espalier.Hashed.HMAC)`, decodes both, requires the HMAC secret to differ from every encryption key, and logs one line at `:info` that names the tags and holds no key material, for example `Encryption keys: AES.GCM.V2 encrypts, AES.GCM.V1 decrypts only`.
4. Configure the keys.
   - In `config/runtime.exs`, inside `if config_env() == :prod do`:
     ```elixir
     cloak_keys =
       for {"CLOAK_KEY_V" <> version, value} <- System.get_env(),
           String.match?(version, ~r/\A[1-9][0-9]*\z/),
           String.trim(value) != "",
           do: {String.to_integer(version), value}

     hmac_secret = System.get_env("CLOAK_HMAC_SECRET", "")

     missing_cloak =
       for {name, missing?} <- [{"CLOAK_KEY_V1", cloak_keys == []}, {"CLOAK_HMAC_SECRET", String.trim(hmac_secret) == ""}],
           missing?,
           do: name

     if missing_cloak != [] do
       raise "Missing environment variables: #{Enum.join(missing_cloak, ", ")}"
     end

     config :espalier, Espalier.Vault, keys: cloak_keys
     config :espalier, Espalier.Hashed.HMAC, secret: hmac_secret
     ```
     Each variable `CLOAK_KEY_V<n>` defines the cipher with the tag `AES.GCM.V<n>`. The highest version encrypts new values, and the others only decrypt. An empty or whitespace-only value counts as missing, so the empty placeholders of `.env.example` and the empty strings that Docker Compose passes for them lead to the missing-variables message, which names `CLOAK_KEY_V1` when no key variable holds a value. 0017 folds `missing_cloak` into its single boot message.
   - In `config/dev.exs`, keys built from a repeated character, so that no high-entropy literal enters the repository:
     ```elixir
     # Invented keys for local data only. Production keys come from CLOAK_KEY_V<n>
     # and CLOAK_HMAC_SECRET (config/runtime.exs).
     config :espalier, Espalier.Vault, keys: [{1, Base.encode64(String.duplicate("d", 32))}]
     config :espalier, Espalier.Hashed.HMAC, secret: Base.encode64(String.duplicate("h", 32))
     ```
     `config/test.exs` holds the same two lines with `"t"` for the cipher key and `"s"` for the HMAC secret.
   - In `.env.example`, add `CLOAK_KEY_V1=` and `CLOAK_HMAC_SECRET=` (both empty) under the comment `# 32 random bytes each, Base64 (make gen-keys or openssl rand -base64 32). Keep them out of database backups. A key rotation adds CLOAK_KEY_V2 (docs/security/key-management.md).`
5. Write `Espalier.Crypto.StrictAESGCM` in `lib/espalier/crypto/strict_aes_gcm.ex`. It is the only module that names `Cloak.Ciphers.AES.GCM`. It keeps the byte format of the wrapped cipher, so a value written with either module can be read by the other.
   ```elixir
   defmodule Espalier.Crypto.StrictAESGCM do
     @moduledoc """
     Cloak.Ciphers.AES.GCM that returns :error when GCM authentication fails.
     The wrapped cipher returns {:ok, :error} for a tampered value or a wrong key.
     """
     @behaviour Cloak.Cipher
     alias Cloak.Ciphers.AES.GCM

     @impl Cloak.Cipher
     defdelegate encrypt(plaintext, opts), to: GCM

     @impl Cloak.Cipher
     defdelegate can_decrypt?(ciphertext, opts), to: GCM

     @impl Cloak.Cipher
     def decrypt(ciphertext, opts) do
       case GCM.decrypt(ciphertext, opts) do
         {:ok, plaintext} when is_binary(plaintext) -> {:ok, plaintext}
         _ -> :error
       end
     end
   end
   ```
6. Write `Espalier.Vault` in `lib/espalier/vault.ex`:
   ```elixir
   defmodule Espalier.Vault do
     use Cloak.Vault, otp_app: :espalier

     alias Espalier.Crypto.{DecryptError, Keys, StrictAESGCM}

     @impl GenServer
     def init(config) do
       ciphers =
         config
         |> Keyword.get(:keys, [])
         |> Keys.cipher_keys!()
         |> Enum.with_index()
         |> Enum.map(fn {{version, key}, index} ->
           label = if index == 0, do: :current, else: :retired
           {label, {StrictAESGCM, tag: "AES.GCM.V#{version}", key: key, iv_length: 12}}
         end)

       {:ok, config |> Keyword.delete(:keys) |> Keyword.put(:ciphers, ciphers)}
     end

     @impl Cloak.Vault
     def decrypt!(ciphertext) do
       case decrypt(ciphertext) do
         {:ok, plaintext} -> plaintext
         {:error, exception} -> raise exception
         :error -> raise DecryptError
       end
     end

     @impl GenServer
     def format_status(%{state: config} = status) do
       %{status | state: Keyword.update(config, :ciphers, [], &redact_keys/1)}
     end

     def format_status(status), do: status

     defp redact_keys(ciphers) do
       for {label, {module, opts}} <- ciphers,
           do: {label, {module, Keyword.put(opts, :key, :redacted)}}
     end
   end
   ```
   The first cipher in the list encrypts all new data whatever its label, and `:retired` entries only decrypt. The labels are fixed atoms, so no atom is created from configuration. Without the `decrypt!/1` override, `Cloak.Vault.decrypt!/2` raises `CaseClauseError` on `:error`. `format_status/1` keeps the keys out of crash reports and `:sys.get_status/1`; Elixir 1.20.4 declares it as an optional `GenServer` callback. `:sys.get_state/1` still returns the full state, which the cipher allowlist test reads.
7. In `lib/espalier/application.ex`, call `Espalier.Crypto.Keys.check!()` as the first expression of `start/2`, insert `Espalier.Vault` into `children` directly before `Espalier.Repo`, and call `Espalier.Telemetry.QueryLog.attach()` when `Application.get_env(:espalier, Espalier.Telemetry.QueryLog, [])[:enabled]` is true.
8. Write the Ecto types, one module per file:
   - `lib/espalier/encrypted/binary.ex`: `use Cloak.Ecto.Binary, vault: Espalier.Vault`.
   - `lib/espalier/encrypted/map.ex`: `use Cloak.Ecto.Map, vault: Espalier.Vault`. Maps are stored as JSON, so atom keys load as string keys.
   - `lib/espalier/encrypted/closure_binary.ex`: `use Cloak.Ecto.Binary, vault: Espalier.Vault, closure: true`. A loaded value is a zero-arity function, which keeps the plaintext out of `inspect/1`, stack traces and JSON. Casting a function stores its result, so a loaded value can be written back unchanged. 0005 uses this type for TOTP secrets.
   - `lib/espalier/hashed/hmac.ex`:
     ```elixir
     defmodule Espalier.Hashed.HMAC do
       use Cloak.Ecto.HMAC, otp_app: :espalier

       @impl Cloak.Ecto.HMAC
       def init(config) do
         secret = Espalier.Crypto.Keys.decode!("CLOAK_HMAC_SECRET", config[:secret])
         {:ok, Keyword.merge(config, algorithm: :sha256, secret: secret)}
       end

       @doc "Returns the keyed hash that dump/1 stores, for plain :binary columns and for comparisons outside a query."
       @spec hash(binary()) :: binary()
       def hash(value) when is_binary(value) do
         {:ok, digest} = dump(value)
         digest
       end
     end
     ```
     `Cloak.Ecto.HMAC` calls `init/1` on every dump, so the secret is decoded once per hash. `init/1` returns a 32-byte binary or raises its own error, because the upstream validation puts an invalid secret into its error message with `inspect/1`. `hash/1` returns the same 32 bytes that a field of this type stores for the same input. `load/1` of the type returns the stored hash, and `dump/1` hashes every binary it receives, so a hash loaded from one row and written into another row through this type is hashed a second time. A keyed hash that moves from row to row therefore lives in a plain `:binary` column that `hash/1` fills once (step 15). The first such column is `users_tokens.idp_sid_hash`: 0006 computes `hash/1` of the provider's `sid` once, the sign-in ticket, the pending second-factor state, the enrollment session and every reissued session row of 0004 to 0006 carry those bytes unchanged, and `delete_sessions_by_idp_sid/2` of 0006 compares with `hash/1` of the presented `sid`. A comparison outside a query, such as the binding check of a sign-in ticket in 0006, also uses `hash/1`.
   Each moduledoc states the rules of step 15: column type `:binary` (`bytea` in PostgreSQL), field option `redact: true`, never inside an embedded schema. The HMAC moduledoc adds that the caller normalizes the value before hashing, because the lookup is case-sensitive, and the rule of step 15 on keyed hashes that move from row to row.
9. Logging, telemetry and the release environment for production.
   - Create `rel/env.sh.eex`. Mix copies this template into every release as `releases/<version>/env.sh`, and the release script `bin/espalier` sources it before every command, including `start`, `eval`, `remote` and `rpc`. The generated Dockerfile copies `rel/` into the build stage.
     ```sh
     #!/bin/sh
     # The BEAM node holds the vault keys, the HMAC secret and decrypted values in
     # memory (docs/security/crypto-inventory.md, Limits (1)).
     # No crash dump file. For a debugging session, set ERL_CRASH_DUMP_BYTES to a
     # size limit and ERL_CRASH_DUMP to a path outside the image; the dump then
     # holds the keys.
     export ERL_CRASH_DUMP_BYTES="${ERL_CRASH_DUMP_BYTES:-0}"
     # No Erlang distribution, so `bin/espalier remote` and `bin/espalier rpc`
     # cannot attach to the running node. `bin/espalier eval` starts a node of its
     # own and keeps working, which the functions in lib/espalier/release.ex rely on.
     export RELEASE_DISTRIBUTION="${RELEASE_DISTRIBUTION:-none}"
     ```
     Both defaults can be overridden from the container environment. An operator who runs several nodes as a cluster (`DNS_CLUSTER_QUERY`) sets `RELEASE_DISTRIBUTION=name` and a random `RELEASE_COOKIE`, and the key management document states that a remote console can then reach the keys.
   - In `config/prod.exs`, set `config :espalier, Espalier.Repo, log: false` and `config :espalier, Espalier.Telemetry.QueryLog, enabled: true`. ecto_sql logs the cast parameters (the plaintext before dump) when they are present, so its own query log stays off in production. Telemetry events are still emitted with `log: false`.
   - Write `Espalier.Telemetry.QueryLog` in `lib/espalier/telemetry/query_log.ex`. `attach/0` attaches the handler id `"espalier-query-log"` to `[:espalier, :repo, :query]`. `scrub/1` drops `:params`, `:cast_params` and `:result` from the metadata map. `format/2` builds one line from `scrub(metadata)` and the measurements: the source, the first word of `:query` and `total_time` in milliseconds. `handle_event/4` logs that line at `:debug`. The moduledoc states that every handler for Repo events calls `scrub/1` first, and that Repo calls take no `log:` option, because a call-level log level overrides `log: false` in ecto_sql.
10. Test support.
    - `test/support/crypto_sample.ex` defines a full schema and its rotation-only schema on one table:
      ```elixir
      defmodule Espalier.Test.CryptoSample do
        use Ecto.Schema
        import Ecto.Changeset

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "crypto_samples" do
          field :email, Espalier.Encrypted.Binary, redact: true
          field :email_hash, Espalier.Hashed.HMAC, redact: true
          field :profile, Espalier.Encrypted.Map, redact: true
          field :secret, Espalier.Encrypted.ClosureBinary, redact: true
          field :status, Ecto.Enum, values: [:active, :disabled]
          timestamps(type: :utc_datetime)
        end

        def changeset(sample, attrs) do
          sample
          |> cast(attrs, [:email, :profile, :secret, :status])
          |> then(&put_change(&1, :email_hash, get_field(&1, :email)))
          |> unique_constraint(:email, name: :crypto_samples_email_hash_index)
        end
      end

      defmodule Espalier.Test.CryptoSampleRotation do
        use Ecto.Schema

        @primary_key {:id, :binary_id, autogenerate: false}
        schema "crypto_samples" do
          field :email, Espalier.Encrypted.Binary, redact: true
          field :profile, Espalier.Encrypted.Map, redact: true
          field :secret, Espalier.Encrypted.ClosureBinary, redact: true
        end
      end
      ```
      The `Ecto.Enum` field and the timestamps give the table the shape on which `mix cloak.migrate.ecto` crashes and changes `updated_at`.
    - `test/support/crypto_case.ex` defines `Espalier.CryptoCase` (`use ExUnit.CaseTemplate`). Its setup runs the sandbox setup of `Espalier.DataCase` and then creates the table inside the sandbox transaction, so the table disappears after each test and needs no migration:
      ```sql
      CREATE TEMP TABLE crypto_samples (
        id uuid PRIMARY KEY, email bytea, email_hash bytea, profile bytea, secret bytea,
        status text, inserted_at timestamp(0) NOT NULL, updated_at timestamp(0) NOT NULL);
      CREATE UNIQUE INDEX crypto_samples_email_hash_index ON crypto_samples (email_hash);
      ```
      It also provides `with_vault_keys(entries, fun)`. The helper saves the current `Espalier.Vault` application environment, sets `keys: entries` with `Application.put_env/3`, restarts the vault with `Supervisor.terminate_child(Espalier.Supervisor, Espalier.Vault)` and `Supervisor.restart_child(Espalier.Supervisor, Espalier.Vault)`, runs `fun`, and restores the environment and the vault in an `after` block. Test modules that call it, read the vault state or attach telemetry handlers set `async: false`.
11. Rotation, in `lib/espalier/crypto/rotation.ex`, module `Espalier.Crypto.Rotation`:
    - `schemas/0` returns the registered rotation-only schemas. The list is empty in this task. Each task that creates an encrypted column adds a rotation-only schema in `lib/espalier/crypto/rotation/<table>.ex` (module `Espalier.Crypto.Rotation.<Table>`, for example `Espalier.Crypto.Rotation.Users`) to this list in the same change, or extends the existing schema of its table, and sets the rows of its columns in `docs/security/crypto-inventory.md` (step 16) to `done`. The registrations are these:
      - 0004 registers `Espalier.Crypto.Rotation.Users` (`lib/espalier/crypto/rotation/users.ex`) with `email`, `display_name` and `org_unit`, `Espalier.Crypto.Rotation.UsersTokens` (`users_tokens.ex`) with `new_email`, and `Espalier.Crypto.Rotation.ExternalIdentities` (`external_identities.ex`) with `subject`.
      - 0005 registers `Espalier.Crypto.Rotation.TotpFactors` (`lib/espalier/crypto/rotation/totp_factors.ex`) with `secret`.
      - 0006 adds `link_identity` to `Espalier.Crypto.Rotation.UsersTokens`.
      - 0007 adds `directory_dn`, `directory_upn` and `directory_login` to `Espalier.Crypto.Rotation.ExternalIdentities`.
    - `validate!(schema)` raises unless the schema has exactly one primary key field and otherwise only fields whose type exports `__cloak__/0`. A rotation-only schema therefore has no timestamps, associations, embeds, `Ecto.Enum` fields, HMAC fields or `user_id` field, and a write through it leaves `updated_at` and the hash columns untouched. It is written by hand, because `mix phx.gen.schema` would add a migration for a table that exists already, timestamps and, with the default scope of 0004, a `user_id` field; `validate!/1` rejects the timestamps and the `user_id` field.
    - `run(repo, schemas, opts \\ [])` validates each schema and walks its table in primary-key order in batches of `opts[:batch_size]` (default 500). Each batch is one transaction: it selects the next rows with `where: r.id > ^last_id` (omitted for the first batch), `order_by: r.id`, `limit: ^batch_size` and `lock: "FOR UPDATE"`, and for each row it applies `Ecto.Changeset.change/1` and `Ecto.Changeset.force_change/3` on every encrypted field with a non-nil value and calls `repo.update!/1`. The batches run one after another on one connection. Loading decrypts with the cipher whose tag the value carries, and dumping encrypts with the first cipher. The function returns `%{schema => rows_updated}`. It can run while the application serves requests, because the row lock makes a concurrent write wait. A second run rewrites the rows again under the current key.
    - `tag_counts(repo, schemas)` returns `%{{table, column} => %{tag => count}}` from one query per encrypted column: `SELECT convert_from(substring(col from 3 for get_byte(col, 1)), 'UTF8'), count(*) FROM table WHERE col IS NOT NULL GROUP BY 1`. A Cloak value starts with `<<1, tag_length, tag::binary>>`, followed by the 12-byte IV, the 16-byte GCM tag and the ciphertext. Table and column names come from `__schema__(:source)` and `__schema__(:field_source, field)` and are quoted as identifiers.
    - `uncovered(schema_modules, rotation_schemas)` returns every `{table, column}` of an encrypted field in `schema_modules` that no rotation schema with the same source covers.
    - In `lib/espalier/release.ex` (generated by `phx.gen.release`), add `rotate_encryption/0` and `encryption_status/0`. Both call the generated `load_app/0` and `Espalier.Crypto.Keys.check!/0`, start the vault with `Espalier.Vault.start_link()` (the result `{:error, {:already_started, _}}` counts as success) and run inside `Ecto.Migrator.with_repo/2` for each repo. `rotate_encryption/0` calls `Rotation.run/2` with `Rotation.schemas()` and prints the row counts and the tag counts. `encryption_status/0` prints the tag counts only. Neither prints a value or a key.
    - `mix cloak.migrate.ecto` is not used. On Ecto 3.12 and later it crashes on schemas with `Ecto.Enum` or embedded fields, it changes `updated_at` on every row of a schema with timestamps, and a release contains no Mix tasks.
12. Schema rules, in `lib/espalier/crypto/schema_rules.ex`, module `Espalier.Crypto.SchemaRules`:
    - `app_schemas/0` returns every module of `Application.spec(:espalier, :modules)` that exports `__schema__/1`, except modules under `Espalier.Test`.
    - `cloak_type?(type)` is true for a module that exports `__cloak__/0`, for `Espalier.Hashed.HMAC` and for every module under `Cloak.`. It looks inside `{:array, type}`, `{:map, type}` and `{:parameterized, {module, _}}`.
    - `embedded_cloak_fields(modules)` returns every `{module, field}` where the module is an embedded schema (`__schema__(:source)` is `nil`) and the field type satisfies `cloak_type?/1`. Cloak types define `embed_as(:self)`, so such a field would be written into the parent's JSON column as plaintext.
    - `unredacted_cloak_fields(modules)` returns every field that satisfies `cloak_type?/1` and is missing from `__schema__(:redact_fields)`.
13. Tests under `test/espalier/crypto/`:
    - `keys_test.exs`: a valid key decodes to 32 bytes; `nil`, `""`, invalid Base64, 31 bytes and 33 bytes raise `InvalidKeyError`; duplicate versions, duplicate keys and an HMAC secret equal to a cipher key raise; no error message contains the input; `cipher_keys!([{1, a}, {2, b}])` returns version 2 first.
    - `strict_aes_gcm_test.exs`: a value round-trips; the ciphertext of a 17-byte value under the tag `AES.GCM.V1` is 57 bytes long and starts with `<<1, 10, "AES.GCM.V1">>`; flipping one bit in the IV, in the GCM tag or in the last byte returns `:error`; a different key under the same tag returns `:error`; `Cloak.Ciphers.AES.GCM.decrypt/2` returns `{:ok, :error}` for the same tampered input. The last assertion records the upstream behavior. When it fails after an upgrade, upstream has changed the cipher, and the wrapper needs a review.
    - `cipher_allowlist_test.exs` (`async: false`): (a) `Espalier.Vault.init/1` on the configured keys and on `[{2, k2}, {1, k1}]` returns only `{Espalier.Crypto.StrictAESGCM, opts}` entries with `iv_length: 12`, a 32-byte key and a tag that matches `~r/\AAES\.GCM\.V[1-9][0-9]*\z/`, highest version first; (b) the `:ciphers` of `:sys.get_state(Espalier.Vault)` pass the same check; (c) a scan of every `.ex` and `.exs` file under `lib/` and `config/` finds `Cloak.Ciphers.` only in `lib/espalier/crypto/strict_aes_gcm.ex`, finds `use Cloak.` only in `lib/espalier/vault.ex`, `lib/espalier/encrypted/` and `lib/espalier/hashed/`, and finds none of `AES.CTR`, `Cloak.Ciphers.Deprecated`, `Cloak.Ecto.PBKDF2` and `Cloak.Ecto.SHA256`; (d) the same scan finds no line that matches `Repo\.\w+\(.*\blog:`.
    - `encrypted_types_test.exs` (`use Espalier.CryptoCase, async: true`): a sample with all four values reads back (the map with string keys, the secret through `sample.secret.()`); the raw `email` column, read with `Repo.query!/2`, starts with `<<1, 10, "AES.GCM.V1">>` and does not contain the plaintext; `Repo.get_by(CryptoSample, email_hash: "a@example.org")` finds the row, the raw `email_hash` equals `:crypto.mac(:hmac, :sha256, String.duplicate("s", 32), "a@example.org")`, and the lookup with `"A@example.org"` returns `nil`; `Espalier.Hashed.HMAC.hash("a@example.org")` equals the raw `email_hash`; the loaded struct's `email_hash` equals the raw column, and a second sample inserted with `Ecto.Changeset.change(%CryptoSample{}, email_hash: loaded.email_hash)` stores `hash(hash("a@example.org"))` in its raw column, which records that the type hashes a loaded hash again; a second insert with the same e-mail returns `{:error, changeset}` with `constraint_name: "crypto_samples_email_hash_index"`; `inspect/1` of the inserted and of the loaded struct contains neither the e-mail nor the secret; `Espalier.Hashed.HMAC.init(secret: valid_base64, algorithm: :md5)` returns `algorithm: :sha256`.
    - `tamper_test.exs` (`async: false`): for each of `email`, `profile` and `secret`, flipping the last byte of the raw column with `Repo.query!/2` makes `Repo.get!/2` raise `ArgumentError` with a message that matches `~r/cannot load/`; a row written under the test key raises the same way inside `with_vault_keys([{1, other_key}], ...)`; a V1 row raises inside `with_vault_keys([{2, other_key}], ...)`, because no configured cipher carries its tag; `Espalier.Vault.decrypt!/1` on a tampered value raises `Espalier.Crypto.DecryptError`.
    - `rotation_test.exs` (`async: false`): insert three samples under V1, one with `profile: nil`, and set `updated_at` to `2000-01-01 00:00:00` with `Repo.query!/2`; inside `with_vault_keys([{2, k2}, {1, test_key}], ...)`, `Rotation.run(Repo, [CryptoSampleRotation])` returns `%{CryptoSampleRotation => 3}`, and `tag_counts/2` reports only `AES.GCM.V2` for `email`, `profile` and `secret`; inside `with_vault_keys([{2, k2}], ...)`, every row reads back, the HMAC lookup still finds its row, and `updated_at` is still `2000-01-01 00:00:00`; `validate!(CryptoSample)` raises; `uncovered([CryptoSample], [])` returns the three encrypted columns, `uncovered([CryptoSample], [CryptoSampleRotation])` returns `[]`, and `uncovered(SchemaRules.app_schemas(), Rotation.schemas())` returns `[]`.
    - `schema_rules_test.exs`: `embedded_cloak_fields/1` and `unredacted_cloak_fields/1` return `[]` for `SchemaRules.app_schemas()`; an embedded schema defined in the test file with a `Espalier.Encrypted.Binary` field and a `Espalier.Hashed.HMAC` field is reported with both fields; a schema in the test file with an encrypted field without `redact: true` is reported.
    - `query_log_test.exs` (`use Espalier.CryptoCase, async: false`): `Config.Reader.read!("config/prod.exs", env: :prod)` holds `log: false` for `Espalier.Repo` and `enabled: true` for `Espalier.Telemetry.QueryLog`; a handler attached in the test with `:telemetry.attach/4` under an id that starts with `"test-"` sends the measurements and metadata of an insert to the test process, where the e-mail is a canary value; the test asserts that `cast_params` contains the canary, which verifies the logging hazard on the pinned toolchain, and that neither `inspect(QueryLog.scrub(metadata))` nor `QueryLog.format(measurements, metadata)` contains it; every handler id in `:telemetry.list_handlers([:espalier, :repo, :query])` is `"espalier-query-log"` or starts with `"test-"`.
    - `inventory_test.exs`: every field of `SchemaRules.app_schemas()` that satisfies `cloak_type?/1`, and every field whose name ends in `_hash` or `_hmac` or equals `hashed_password`, appears in `docs/security/crypto-inventory.md` as `` `table.column` ``. The name rule covers the plain `:binary` columns of the levels `keyed hash`, `hash` and `password hash`, which no Cloak type marks.
14. Write `scripts/gen-keys.exs`. It prints `CLOAK_KEY_V1=<value>` and `CLOAK_HMAC_SECRET=<value>`, each value from `32 |> :crypto.strong_rand_bytes() |> Base.encode64()`. Add the Makefile target `gen-keys: ## print new CLOAK_KEY_V1 and CLOAK_HMAC_SECRET values for .env`, which runs `$(NIX) "elixir scripts/gen-keys.exs"`.
15. Extend the section "Project rules" in `AGENTS.md` with these rules:
    - A column with personal data or an authenticator secret has the column type `:binary` and one of the Ecto types `Espalier.Encrypted.Binary`, `Espalier.Encrypted.Map` or `Espalier.Encrypted.ClosureBinary`, with `redact: true`. A column for lookups by such a value has the type `Espalier.Hashed.HMAC`, with `redact: true`, and the changeset fills it from the normalized plaintext.
    - A keyed hash that is copied from one row into another, or carried through the session or a sign-in ticket, has a plain `:binary` field with `redact: true`. Its value comes once from `Espalier.Hashed.HMAC.hash/1` of the normalized plaintext, every copy takes the stored bytes unchanged, and every lookup compares with `hash/1` of the presented value. The Ecto type `Espalier.Hashed.HMAC` hashes every value it dumps, so a loaded hash written through it is hashed a second time and matches no lookup.
    - No encrypted or hashed type appears inside `embedded_schema`, `embeds_one` or `embeds_many`. Structured personal data goes into one `Espalier.Encrypted.Map` column.
    - Every table with an encrypted column gets a rotation-only schema `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/<table>.ex`, registered in `Espalier.Crypto.Rotation.schemas/0`, and every encrypted, hashed or password-hash column gets a row in `docs/security/crypto-inventory.md`, both in the same change.
    - A value encrypted with `Espalier.Vault.encrypt!/1` outside an Ecto type, such as an address in Oban job arguments, gets a row in the section "Values encrypted outside Ecto types" of `docs/security/crypto-inventory.md` with its location and its lifetime in the same change. `rotate_encryption/0` does not rewrite such values, so the rotation runbook waits until no value under the old tag is still read.
    - Only `lib/espalier/vault.ex`, `lib/espalier/crypto/`, `lib/espalier/encrypted/` and `lib/espalier/hashed/` call Cloak.
    - Repo calls take no `log:` option, and a telemetry handler for Repo events calls `Espalier.Telemetry.QueryLog.scrub/1` first.
    - A data migration that writes an encrypted field calls `Espalier.Vault.start_link()` first, because `mix ecto.migrate` and `bin/migrate` do not start the application.
16. Write `docs/security/crypto-inventory.md` with these sections:
    - **Threat model.** Cloak protects stored columns against someone who holds a database dump, replica or backup without the keys (README section 6.9).
    - **Protection levels** (ASVS 14.1.1 and 14.1.2). A table gives the data, storage, lookup, logging and rotation of each level:

      | Level | Data | Storage | Lookup | Logging | Rotation |
      |---|---|---|---|---|---|
      | `encrypted` | personal data and authenticator secrets that the application reads back | AES-256-GCM through `Espalier.Encrypted.*` | only through a keyed hash column | never | `rotate_encryption/0` |
      | `keyed hash` | lookup values for encrypted data and for the identity provider's session id, and recovery codes and the bindings of sign-in tickets and OIDC intents that the application only compares | HMAC-SHA256 under `CLOAK_HMAC_SECRET` through the type `Espalier.Hashed.HMAC`, or through `Espalier.Hashed.HMAC.hash/1` into a plain `:binary` column for a value copied between rows, or under a key derived from `CLOAK_HMAC_SECRET` | equality only | never | none in the first version |
      | `hash` | random secrets of at least 128 bits that the application only compares | SHA-256 | hash of the presented value | never | a new secret replaces the old one |
      | `password hash` | passwords | Argon2id | verification only | never | not applicable |
      | `plain` | values without personal or secret content | plain column | any SQL | allowed | not applicable |

    - **Columns.** A table lists every protected column with the columns Column, Level, Type or function, Key, Task and Status. The Key column names `CLOAK_KEY_V<n>` for `encrypted`, `CLOAK_HMAC_SECRET` or the key derived from it for `keyed hash`, and no key for the other levels. Every row starts with the status `planned` and the task that creates the column; that task sets `done` and names its module. These are the rows:

      | Column | Level | Type or function | Task |
      |---|---|---|---|
      | `users.email` | `encrypted` | `Espalier.Encrypted.Binary` | 0004 |
      | `users.display_name` | `encrypted` | `Espalier.Encrypted.Binary` | 0004 |
      | `users.org_unit` | `encrypted` | `Espalier.Encrypted.Binary` | 0004 |
      | `users.email_hash` | `keyed hash` | `Espalier.Hashed.HMAC` of the trimmed, lower-cased address, unique index | 0004 |
      | `users.hashed_password` | `password hash` | Argon2id with `argon2_elixir` | 0004 |
      | `users_tokens.token_hash` | `hash` | SHA-256 of a 32-byte random token for the contexts `session`, `invite`, `change_email`, `recovery_email` and `login_ticket`, and `oidc_intent` from 0006 | 0004 |
      | `users_tokens.sent_to_hash` | `keyed hash` | `Espalier.Hashed.HMAC` | 0004 |
      | `users_tokens.new_email` | `encrypted` | `Espalier.Encrypted.Binary` | 0004 |
      | `users_tokens.idp_sid_hash` | `keyed hash` | plain `:binary` column with `Espalier.Hashed.HMAC.hash/1` of the provider's `sid`, computed once by 0006 and copied unchanged through the sign-in ticket, the pending second-factor state, the enrollment session and every reissued session row; lookups compare with `hash/1` of the presented `sid` | 0004 |
      | `users_tokens.binding_hash` | `keyed hash` | `Espalier.Hashed.HMAC` of the Base64url-encoded 32-byte binding of a sign-in ticket, or of the id of the session that created an OIDC intent | 0006 |
      | `users_tokens.link_identity` | `encrypted` | `Espalier.Encrypted.Binary` (issuer, tenant id and subject of an identity to link) | 0006 |
      | `api_clients.token_hash` | `hash` | SHA-256 of a 32-byte random token | 0004 |
      | `external_identities.subject` | `encrypted` | `Espalier.Encrypted.Binary`, written by 0004 (demo identities), 0006 and 0007 | 0004 |
      | `external_identities.subject_hash` | `keyed hash` | `Espalier.Hashed.HMAC` of `Espalier.Accounts.ExternalIdentity.hash_input(issuer, tenant_id, subject)` of 0004, unique index with `provider_key`; written by 0004 (demo identities), 0006 and 0007 | 0004 |
      | `external_identities.directory_dn` | `encrypted` | `Espalier.Encrypted.Binary` | 0007 |
      | `external_identities.directory_upn` | `encrypted` | `Espalier.Encrypted.Binary` | 0007 |
      | `external_identities.directory_login` | `encrypted` | `Espalier.Encrypted.Binary` | 0007 |
      | `failure_counters.subject_hash` | `keyed hash` | `Espalier.Hashed.HMAC` of the same input as `external_identities.subject_hash` | 0007 |
      | `totp_factors.secret` | `encrypted` | `Espalier.Encrypted.ClosureBinary` | 0005 |
      | `recovery_codes.code_hmac` | `keyed hash` | HMAC-SHA256 under the key that 0005 derives from `CLOAK_HMAC_SECRET` with the label `espalier/recovery-codes/v1` | 0005 |

    - **Values encrypted outside Ecto types** (step 15). A table gives location, content, encryption, lifetime, task and status of each value that `Espalier.Vault.encrypt!/1` produces and no Ecto type stores. The first row starts with the status `planned`:

      | Location | Content | Encryption | Lifetime | Task |
      |---|---|---|---|---|
      | `oban_jobs.args` of `Espalier.Accounts.MailWorker` | e-mail addresses of the mail kinds of 0004 steps 20 and 27 | `Espalier.Vault.encrypt!/1`, Base64 | read while the job is `available`, `scheduled`, `executing` or `retryable`; the finished row stays until the Oban pruner of 0004 deletes it | 0004 |

    - **Keys and algorithms outside the database.** A table gives one row per key with its algorithm, its location and the task that introduces it. The rows are `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET` (this task); the recovery-code key, which 0005 derives from `CLOAK_HMAC_SECRET` as HMAC-SHA256 over the label `espalier/recovery-codes/v1` (README section 6.6); `SECRET_KEY_BASE` for Phoenix signing and the encrypted `Plug.Session` cookie (0001, 0004); the rate-limit key, which 0004 derives once at boot with `Plug.Crypto.KeyGenerator.generate(secret_key_base, "espalier rate limit", length: 32)`, keeps in `:persistent_term` and uses for HMAC-SHA256 over normalized identifiers; session tokens from `:crypto.strong_rand_bytes(32)` (0004); the OIDC client certificate and key for `private_key_jwt` (0006); the OIDC client secrets `AUTH_<KEY>_CLIENT_SECRET`, which the client presents to the token endpoint with `client_secret_basic` or `client_secret_post` (0006); the LDAP CA certificate (0007); the LDAP bind password `AUTH_LDAP_BIND_PASSWORD` of the service account, which the service bind sends inside the TLS connection (0007); and webhook secrets for HMAC-SHA256 signatures (0013). The location of `CLOAK_KEY_V<n>` names the environment, the vault ETS table, the vault state and the application environment; the location of `CLOAK_HMAC_SECRET` names the environment and the application environment (Limits (1)). The location of `AUTH_<KEY>_CLIENT_SECRET` and of `AUTH_LDAP_BIND_PASSWORD` names the environment and the provider structs under `:identity_providers` in the application environment. 0006 completes the row of `AUTH_<KEY>_CLIENT_SECRET`, 0007 the row of `AUTH_LDAP_BIND_PASSWORD` and 0013 the row of the webhook secrets, each with the module that reads the secret.
    - **Limits.** (1) Keys and plaintext live in the memory of the BEAM node. The cipher keys sit in the `:protected` ETS table `:"Elixir.Espalier.Vault.Config"`, which every process on the node can read, in the vault state, and Base64-encoded in the application environment under `Espalier.Vault`, where `config/runtime.exs` puts them. The HMAC secret never enters the vault; it stays Base64-encoded in the application environment under `Espalier.Hashed.HMAC`, which `Cloak.Ecto.HMAC` reads on every dump. `format_status/1` hides the keys in the vault state and has no effect on the application environment, which every process reads with `Application.get_env/2`. Crash dumps and remote consoles reach all of these places, so the release environment of step 9 (`rel/env.sh.eex`) writes no crash dump file and starts no Erlang distribution unless the operator overrides it. (2) Query logs and telemetry carry plaintext when the rules of step 15 are broken. (3) A backup that holds both the database and the keys protects nothing. (4) The ciphertext length reveals the plaintext length, because Cloak adds no padding. (5) Keyed hashes reveal which rows hold equal values, and with the dump and the HMAC secret, low-entropy values such as e-mail addresses can be guessed offline. (6) The AAD is the constant `"AES256GCM"`, so someone with write access to the database can copy a valid ciphertext into another row or column under the same key without detection; that attacker is outside the threat model, and the fallback plan binds the AAD to table and column. (7) SQL cannot sort, range-filter or search encrypted columns. (8) An attacker who runs code inside the application is not stopped. (9) A failed load raises `ArgumentError` with the ciphertext in its message, and a failed dump raises `Ecto.ChangeError` with the plaintext in its message; a dump fails when the vault is not running, which the supervision order and the data migration rule of step 15 prevent.
17. Write `docs/security/key-management.md` with these sections:
    - **Keys.** A table gives name, purpose, format, generation, storage and rotation for `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET`.
    - **Generation.** Keys are generated with `make gen-keys`, or with `openssl rand -base64 32` once per key on a machine without the toolchain.
    - **Storage and access.** Keys come from the environment, filled from the operator's secret store. They never enter the repository, the database, a log or the backup set of the database. Only the people who deploy the application can read them; developers work with the dev keys. For every key version that still protects data in live rows or in a retained backup, an offline copy is kept apart from the database backups. Losing every copy of such a key makes those values unreadable for good.
    - **Boot checks.** This section lists the checks of steps 3 and 4 with their messages and shows the boot log line that names the tags.
    - **Memory of the running node.** The release environment of step 9 sets `ERL_CRASH_DUMP_BYTES=0` and `RELEASE_DISTRIBUTION=none` as defaults, because a crash dump or a remote console reaches the keys (`docs/security/crypto-inventory.md`, Limits (1)). The section states that an operator who overrides either default for debugging or for a cluster lets a crash dump or a remote console reach the keys, and that a crash dump file needs the same protection as the keys themselves.
    - **Cryptoperiod and rotation triggers.** The operator sets a cryptoperiod for the encryption key. NIST SP 800-57 Part 1 gives reference values; check the current version of that publication before writing a number into this section. Rotate earlier after a suspected exposure, when a person with key access leaves, and before 2^32 encryptions under one key, the limit that NIST SP 800-38D (section 8.3) sets for random 96-bit IVs. Each write of an encrypted field counts as one encryption.
    - **Runbook: rotate the encryption key.** (1) Generate a key and store it as `CLOAK_KEY_V2`; keep `CLOAK_KEY_V1`. (2) Restart every application node; the boot log shows `AES.GCM.V2 encrypts, AES.GCM.V1 decrypts only`. Note the UTC time at which the last node has restarted. (3) Run `docker compose exec app bin/espalier eval "Espalier.Release.rotate_encryption()"` (in a plain release, `bin/espalier eval` with the same expression). (4) Run `Espalier.Release.encryption_status()` the same way and confirm that every column reports only `AES.GCM.V2`. (5) Wait for the values of the section "Values encrypted outside Ecto types" of `docs/security/crypto-inventory.md`, which the rotation does not rewrite. For the Oban mail jobs of 0004, run `SELECT count(*) FROM oban_jobs WHERE inserted_at < '<time of step 2>' AND state IN ('available', 'scheduled', 'executing', 'retryable')` in `psql` and repeat it until it returns 0. (6) Take a new database backup. (7) Remove `CLOAK_KEY_V1` from the environment and restart. Every backup taken before the backup of step 6, including a backup taken while step 3 ran, still holds V1 values, so the offline copy of V1 stays until every backup taken before the backup of step 6 has expired. If step 3 stops halfway, the table holds V1 and V2 values side by side, both stay readable while both keys are configured, and step 3 can run again.
    - **HMAC secret.** The first version has no rotation for `CLOAK_HMAC_SECRET`, because Cloak cannot re-hash a value without its plaintext. The secret alone reveals no data; together with a dump it allows offline guessing of hashed values. A change of the secret also invalidates every stored recovery code, because the recovery-code key derives from it (README section 6.6), so every user then regenerates the codes. A rotation needs a second hash column per lookup, filled from the decrypted plaintext, a switch of every lookup, and the removal of the old column. That work is a task of its own.
    - **Upstream status and fallback plan.** The pinned versions are `cloak` 1.1.4 and `cloak_ecto` 1.3.0; both were released on 2024-04-06, and both have one owner on Hex. The watch list works as follows: at every Espalier release, and whenever `mix hex.audit` or `mix deps.get` reports a new advisory, the maintainer runs `mix hex.outdated`, reads the advisory tracking issues cloak#132 and cloak_ecto#66, the release request cloak_ecto#64, cloak_ecto PR #58 (`Ecto.Enum` fix) and cloak PR #128 (12-byte IV default), and records the date and the result in this section. An upstream release is adopted after a review of its `lib/` diff against the pinned version and a green run of `test/espalier/crypto/`, again pinned exactly. The fallback starts when one of these triggers fires: (a) an advisory affects `Cloak.Ciphers.AES.GCM`, `Cloak.Vault`, `Cloak.Ecto.Type`, `Cloak.Ecto.Binary`, `Cloak.Ecto.Map` or `Cloak.Ecto.HMAC`; (b) an Elixir, OTP or Ecto release that the project adopts stops compiling `cloak` or `cloak_ecto` or makes a test under `test/espalier/crypto/` fail; (c) the threat model grows to an attacker with write access to the database. A fourth trigger covers continued upstream inactivity (README section 6.9): (d) the review date recorded in this section has passed, and since the previous review neither package has published a release that fixes EEF-CVE-2026-95105 or EEF-CVE-2026-94206 or contains the fix of cloak_ecto PR #58. This task records the first review date, six months after its merge. When trigger (d) fires, the maintainer either opens the fallback task or records in this section a decision to keep the pins, with the date, the reason and a new review date at most six months later. The fallback stays inside the application and uses no fork as a Git dependency. It is one change with these parts: `Espalier.Crypto.AESGCM` on `:crypto.crypto_one_time_aead/6` and `/7` (AES-256-GCM, 12-byte IV from `:crypto.strong_rand_bytes/1`, 16-byte tag, failure returns `:error`) reads the Cloak format `<<1, tag_length, tag, iv::binary-12, gcm_tag::binary-16, ciphertext>>` with the AAD `"AES256GCM"` for the existing tags and writes a new tag whose AAD names table and column; `Espalier.Encrypted.*` become own `Ecto.ParameterizedType` modules under the same module names, so migrations stay unchanged; every encrypted field in a full schema and in its rotation-only schema gains the option `aad:` with its table and column, for example `field :email, Espalier.Encrypted.Binary, redact: true, aad: "users.email"`, and `init/1` raises when the option is missing; the AAD comes from this option, because Ecto passes the schema module and the field name to `init/1` and no table name, and a full schema and its rotation-only schema are two modules on one table, so an AAD derived from the module would differ between them and the rotation could not read the values; `Espalier.Crypto.Rotation` and `Espalier.Crypto.SchemaRules` read the module from `{:parameterized, {module, params}}`, as `cloak_type?/1` already does; `Espalier.Hashed.HMAC` computes `:crypto.mac(:hmac, :sha256, secret, value)` in `dump/1` and `hash/1`, the same bytes that `Cloak.Ecto.HMAC` stores, so every hash column stays valid; `rotate_encryption/0` moves all rows to the new tag, after which `cloak` and `cloak_ecto` leave `mix.exs` together with the `ignore_advisories` entries; the tests under `test/espalier/crypto/` run against the new modules, except the assertions that record upstream behavior.
18. Create `docs/security/asvs-l2.md` in exactly the layout that 0004 step 42 prescribes. 0004 extends the same file and holds the ownership table that assigns every row to its tasks, and every later security task fills its rows. The file has a short header (ASVS 5.0.0, tag `v5.0.0_release` of the OWASP ASVS repository, Level 2 target, selected Level 3 items of README section 6.1), the status values `open`, `implemented`, `verified`, `deviation` and `not applicable`, one table per chapter with the columns `ID`, `Level`, `Requirement` (a few words), `Task`, `Status`, `Code`, `Test` and `Notes`, and a section `Deviations`. Add one row per requirement in the section "Security requirements" above, in the tables V11, V13, V14 and V16. The `Task` column lists the owner first and then the extending tasks, separated by commas, exactly as the ownership table of 0004 step 42 gives them. Each row names the module or document from the steps above in `Code` and the test file under `test/espalier/crypto/` that proves it in `Test`. The operator part of 13.3.1 and 13.3.2 points to `docs/security/key-management.md`. A row that this task completes alone carries the task `0003` and the status `verified`. These seven rows need later work; each carries the status `open`, the `Task` value given below, and in `Notes` what this task delivers and what remains:
    - 11.1.1 (`0003, 0017`): this task documents the lifecycle of `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET` in `docs/security/key-management.md`, and 0017 adds the lifecycle of the deployment secrets and certificates (rotation of `SECRET_KEY_BASE` and API tokens, renewal of the database certificates) to `docs/security/key-management.md` (0017 step 13), which `docs/guides/operations.md` and `docs/guides/security.md` link (0017 step 11).
    - 11.1.2 (`0003, 0017`): this task lists the keys, algorithms and protected columns of the account tasks in `docs/security/crypto-inventory.md`, and 0017 adds the certificates of the production deployment (the CA certificate of the PostgreSQL connection in `DATABASE_CA_CERT_FILE` and the TLS settings of the reverse proxy example).
    - 11.5.1 (`0003, 0004, 0005`): this task generates the Cloak keys, 0004 adds session, e-mail and API tokens, and 0005 adds recovery codes, TOTP secrets, WebAuthn challenges and user handles.
    - 13.3.1 (`0003, 0006, 0007, 0013, 0017`): this task covers the Cloak keys, 0006 the OIDC client secrets and the key of the client certificate, 0007 the LDAP bind password, 0013 the webhook secrets, and 0017 every other secret, the image and the Git history.
    - 14.1.1 (`0003`): this task classifies account and authentication data, and the data protection workstream of README section 10 adds the other data classes. The row stays `open` until that workstream has classified them.
    - 16.2.5 (`0003, 0004, 0005, 0006, 0007, 0013`): this task keeps plaintext out of query logs and telemetry, 0004 adds request and security event logs, 0005 keeps codes and factor secrets out of the logs, 0006 keeps authorization codes, ID tokens, tickets and intents out of the logs, 0007 keeps the bind request and LDAP exception texts out of the logs, and 0013 keeps API tokens, webhook secrets and signatures out of the logs.
    - 16.5.3 (`0003, 0006, 0007`): this task makes a failed decryption raise, and 0006 and 0007 make the sign-in fail closed when an identity provider or the directory is unreachable.

## Deliverables
- `mix.exs` and `mix.lock` with the pinned dependencies and the `hex: [ignore_advisories: ...]` entry with its reason comment.
- `lib/espalier/vault.ex`, `lib/espalier/crypto/{keys,errors,strict_aes_gcm,rotation,schema_rules}.ex`, `lib/espalier/encrypted/{binary,map,closure_binary}.ex`, `lib/espalier/hashed/hmac.ex`, `lib/espalier/telemetry/query_log.ex`, and the changes to `lib/espalier/application.ex` and `lib/espalier/release.ex`.
- `config/runtime.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs`, `.env.example` and `rel/env.sh.eex`.
- `test/support/crypto_sample.ex`, `test/support/crypto_case.ex` and the nine test files of step 13.
- `scripts/gen-keys.exs`, the Makefile target `gen-keys`, and the rules in `AGENTS.md`.
- `docs/security/crypto-inventory.md`, `docs/security/key-management.md`, and `docs/security/asvs-l2.md` in the layout of 0004 step 42 with the rows of step 18.

## Acceptance
- [ ] `nix-shell --run "mix hex.info"` prints `Hex: 2.5.1` or later.
- [ ] `nix-shell --run "mix hex.audit"` exits 0 and lists `EEF-CVE-2026-95105` and `EEF-CVE-2026-94206` under `Ignored advisories:`. With the `ignore_advisories` line commented out, it exits 1; the line is restored afterwards.
- [ ] `grep -cE '"cloak": \{:hex, :cloak, "1\.1\.4"|"cloak_ecto": \{:hex, :cloak_ecto, "1\.3\.0"' mix.lock` prints `2`.
- [ ] `nix-shell --run "mix test test/espalier/crypto"` passes.
- [ ] Replacing `StrictAESGCM` with `Cloak.Ciphers.AES.GCM` in `Espalier.Vault.init/1` makes `cipher_allowlist_test.exs` and `tamper_test.exs` fail; reverting the change makes them pass.
- [ ] Adding `field :phone, Espalier.Encrypted.Binary` to an embedded schema under `lib/` makes `schema_rules_test.exs` fail; removing it makes it pass.
- [ ] `make gen-keys` prints two lines that match `^CLOAK_(KEY_V1|HMAC_SECRET)=[A-Za-z0-9+/]{43}=$`, with new values on every run.
- [ ] With generated keys in `.env`, `make docker-build docker-up` serves `/health`, and `docker compose exec app bin/espalier eval "Espalier.Release.rotate_encryption()"` and the same call with `encryption_status()` exit 0.
- [ ] With `CLOAK_HMAC_SECRET` removed from `.env`, the app container stops at boot, and `make docker-logs` shows an error that names `CLOAK_HMAC_SECRET`. With `CLOAK_KEY_V1=` left empty as in `.env.example`, the missing-variables error names `CLOAK_KEY_V1`. With `CLOAK_KEY_V1` set to the output of `openssl rand -base64 31`, the error names `CLOAK_KEY_V1`, and the log does not contain that value.
- [ ] With the container running, `docker compose exec app bin/espalier eval 'IO.puts(System.get_env("ERL_CRASH_DUMP_BYTES") <> " " <> System.get_env("RELEASE_DISTRIBUTION"))'` prints `0 none`, and `docker compose exec app bin/espalier rpc "IO.puts(:connected)"` fails with an `--rpc-eval` error and prints no `connected`.
- [ ] `grep -rnE 'Cloak\.Ciphers\.AES\.CTR|Cloak\.Ecto\.PBKDF2|Cloak\.Ecto\.SHA256' lib config` prints nothing.
- [ ] `make secrets-scan` exits 0 with the dev and test keys in place (once 0002 has added the target).
- [ ] `docs/security/crypto-inventory.md` lists every encrypted and keyed-hash column of README section 6.9 with the level that section gives it, the columns `users.hashed_password`, `users_tokens.token_hash` and `api_clients.token_hash`, and the row `oban_jobs.args`. `docs/security/key-management.md` contains the rotation runbook with the wait for job arguments, the fallback plan with trigger (d) and its first review date, and the section on the memory of the running node.
- [ ] `docs/security/asvs-l2.md` has the columns `ID`, `Level`, `Requirement`, `Task`, `Status`, `Code`, `Test` and `Notes`, uses only the status values `open`, `implemented`, `verified`, `deviation` and `not applicable`, and has a section `Deviations`.
- [ ] The rows of `docs/security/asvs-l2.md` for the listed requirements name the code and the test, and their `Task` column matches the ownership table of 0004 step 42.
- [ ] `make check` passes.

## Notes
- Versions: `cloak` 1.1.4 and `cloak_ecto` 1.3.0 are the latest Hex releases, both published on 2024-04-06, with one owner (hex.pm API, retrieved 2026-10-07). `cloak_ecto` 1.3.0 requires `cloak ~> 1.1.1` and `ecto ~> 3.0` (`mix.exs` of the package). The CI matrix of `cloak_ecto` master ends at Elixir 1.16.0 and Erlang 26.0 (`.semaphore/semaphore.yml`, last commit 9989e73 of 2024-10-29), and the CI of `cloak` master runs Elixir 1.19.5 on Erlang 28.4 (cloak PR #130, merged in commit 9a3d10c of 2026-03-14). The pinned toolchain of README section 3 (Elixir 1.20.4, OTP 28.5.0.7, Ecto 3.14.2, ecto_sql 3.14.0, PostgreSQL 18.6) lies outside both matrices, so the tests of step 13 serve as the compatibility check on that toolchain. Compiling `cloak` 1.1.4 with Elixir 1.20.4 prints four deprecation warnings, and compiling `cloak_ecto` 1.3.0 prints one type warning; `mix compile --warnings-as-errors` applies to the project's own modules only.
- Advisories, published by the EEF CNA on 2026-10-06 (https://cna.erlef.org/osv/EEF-CVE-2026-95105.json and https://cna.erlef.org/osv/EEF-CVE-2026-94206.json). EEF-CVE-2026-95105 (HIGH, CVSS 4.0 score 8.2): `Cloak.Ciphers.AES.CTR` and `Cloak.Ciphers.Deprecated.AES.CTR` store no MAC, which affects every `cloak` release from 0.1.0-pre through 1.1.4, with no fixed version. EEF-CVE-2026-94206 (MEDIUM, 6.3): `Cloak.Ecto.PBKDF2.dump/1` passes `:size` where the iteration count belongs, so the defaults run 32 rounds where 600,000 are configured; this affects `cloak_ecto` from 1.0.0-alpha.0 through 1.3.0, with no fixed version. The same OSV record also lists `cloak` 0.7.0 to 0.9.2 (`Cloak.Fields.PBKDF2`) with a fixed event at 1.0.0-alpha.0, so tools that read OSV show `cloak` in that record as well.
- Hex: warnings in `mix deps.get` and `mix deps.update` arrived in Hex 2.5.0 (2026-06-28); `ignore_advisories` and `HEX_IGNORE_ADVISORIES` arrived in Hex 2.5.1 (2026-07-09). An entry matches the primary ID or any alias, ignored findings do not make `mix hex.audit` exit non-zero, and the same setting silences `deps.get` and `deps.update` (hexdocs, `Mix.Tasks.Hex.Audit`, v2.5.1). Older Hex versions do not read the setting.
- GCM: `Cloak.Ciphers.AES.GCM` 1.1.4 defaults to a 16-byte IV, uses the constant AAD `"AES256GCM"`, and wraps the result of `:crypto.crypto_one_time_aead/7` unchecked, so a failed authentication returns `{:ok, :error}` (`lib/cloak/ciphers/aes_gcm.ex`). The decrypt tests of cloak 1.1.4 (`test/cloak/ciphers/aes_gcm_test.exs`) pass a foreign tag or a malformed value, which `can_decrypt?/2` rejects before GCM runs, and none of them changes a ciphertext under its own tag and key. Without the wrapper, a `Cloak.Ecto.Binary` field loads such a value as the atom `:error`, and a `Cloak.Ecto.Map` field raises inside the JSON decoder. The IV length is part of a tag's format: changing `iv_length` for an existing tag makes its values unreadable, so a new IV length needs a new tag. NIST SP 800-38D, section 5.2.1.1, recommends 96-bit IVs. `Cloak.Ciphers.Deprecated.AES.GCM` has the same unchecked decrypt and is never configured.
- Vault: `start_link` merges the application environment into its argument, runs `init/1`, and stores the result in a named `:protected` ETS table; encryption and decryption run in the calling process. `mix ecto.migrate` does not start the vault (cloak_ecto#62).
- Rotation: Ecto 3.12 changed the internal representation of parameterized types to `{:parameterized, {module, params}}`. `Cloak.Ecto.Migrator` 1.3.0 still matches the shapes `{:parameterized, Ecto.Enum, _}` and `{:parameterized, Ecto.Embedded, _}`, so `mix cloak.migrate.ecto` passes the type tuple of an `Ecto.Enum` or embedded field to `Code.ensure_loaded?/1`, which raises `FunctionClauseError` (`lib/cloak_ecto/migrator.ex`; fix in cloak_ecto PR #58, open since 2024-08-28). The migrator writes each row through `Ecto.Changeset.force_change/3` and `repo.update/1`, and Ecto 3.14.2 sets the `autoupdate` fields of a schema on every update with changes (`lib/ecto/repo/schema.ex`), so the migrator changes `updated_at` on every row of a schema with `timestamps()`. A rotation-only schema holds only the primary key and the encrypted fields, so `Rotation.run/3` of step 11 meets neither problem. `Cloak.Ecto.Migrator` is marked `@moduledoc false`.
- Embeds: `Cloak.Ecto.Type` and `Cloak.Ecto.HMAC` define `embed_as(:self)`, so a field of these types inside an embedded schema is stored as plaintext JSON; an embedded `field :phone, Encrypted.Binary` is written as `{"phone": "<plaintext>"}` (cloak#84 and cloak_ecto PR #60 are open).
- HMAC: `Cloak.Ecto.HMAC.dump/1` builds its configuration from the application environment and `init/1` on every call. After `put_change/3` and insert, the struct's hash field still holds the plaintext, which is why hash fields need `redact: true` as well. `dump/1` returns `{:ok, :crypto.mac(:hmac, algorithm, secret, value)}` for every binary, and `load/1` returns the stored bytes unchanged (cloak_ecto 1.3.0, `lib/cloak_ecto/types/hmac.ex` and `lib/cloak_ecto/crypto.ex`). A hash loaded from one row and written into another row through the type is therefore hashed again, which `encrypted_types_test.exs` records and the rule of step 15 on copied hashes avoids.
- Logging: ecto_sql 3.14.0 logs `opts[:cast_params] || params`, emits `params`, `cast_params` and `result` in the telemetry metadata, and lets a call-level `log:` level override `log: false` (`lib/ecto/adapters/sql.ex`). `redact: true` changes only `inspect/1` output. `query_log_test.exs` asserts this behavior on the pinned toolchain. Request parameter logging is outside this task.
- Ecto raises the load error in `lib/ecto/repo/queryable.ex` and the dump error in `lib/ecto/repo/schema.ex` (Ecto 3.14.2). `Ecto.ParameterizedType.init/1` receives the field options merged with `field: name, schema: mod`, where `mod` is the schema module (Ecto 3.14.2, `lib/ecto/schema.ex`, line 2634). The table name reaches only `Ecto.Schema.__schema__/5`, which stores it in the internal module attribute `@ecto_source`; that attribute is no public interface, and `mod.__schema__(:source)` is defined only after the fields. The fallback plan therefore takes the AAD from the explicit `aad:` option. The telemetry prefix of `Espalier.Repo` is `[:espalier, :repo]`.
- Size: each encrypted value grows by 40 bytes with a 10-byte tag (1 type byte, 1 length byte, 10 tag bytes, 12 IV bytes, 16 GCM tag bytes).
- Rotation schemas and inventory rows: each task that adds an encrypted field registers its rotation-only schema in the same change (step 11), because the assertion of `rotation_test.exs` that `uncovered(SchemaRules.app_schemas(), Rotation.schemas())` returns `[]` fails as soon as an encrypted field has no rotation-only schema. `inventory_test.exs` passes at the end of this task, because step 16 lists every column with the status `planned`; each later task sets its rows to `done` and adds a row for any further protected field. This task creates no production table and no route, so it runs no `mix phx.gen.schema`, registers no rotation-only schema and adds no OpenAPI operation (README section 6.12); its only table is the temporary test table of step 10.
- Job arguments: 0004 step 27 stores e-mail addresses in `oban_jobs.args`, encrypted with `Espalier.Vault.encrypt!/1` and Base64-encoded, and 0004 step 20 does the same for the new address of an e-mail change. `rotate_encryption/0` walks Ecto schemas only, which is why the runbook waits for these jobs before the old key leaves the environment.
- Release environment: the `erl` manual page of OTP 28.5.0.7 states that `ERL_CRASH_DUMP_BYTES=0` makes the runtime system write no crash dump file (introduced in ERTS 8.1.2, OTP 19.2), and that without `ERL_CRASH_DUMP` the dump goes to `erl_crash.dump` in the current directory. In Elixir 1.20.4, `mix release` uses `rel/env.sh.eex` when the file exists, the generated `bin/<name>` script sources `env.sh` before every command, `RELEASE_DISTRIBUTION` accepts `sname`, `name` or `none` (default `sname`), `eval` starts without distribution, and `rpc` reports `Cannot run --rpc-eval if the node is not alive` when the calling node is not distributed (`lib/mix/lib/mix/tasks/release.ex`, `lib/mix/lib/mix/tasks/release.init.ex` and `lib/elixir/lib/kernel/cli.ex` in the Elixir repository). `phx.gen.release` 1.8.15 generates `rel/overlays/bin/server` and `rel/overlays/bin/migrate` and no `env.sh.eex`, and its Dockerfile copies `rel` before `mix release`. Phoenix 1.8.15 generates the `DNSCluster` child, which stays inactive while `DNS_CLUSTER_QUERY` is unset.
- ASVS: the IDs above follow the files of OWASP ASVS at tag `v5.0.0_release` (chapters V11, V13, V14 and V16, retrieved 2026-10-07). The tag list of the OWASP ASVS repository holds `v5.0.0_release` and no `v5.0.0` (GitHub API, retrieved 2026-10-07), so step 18 writes `v5.0.0_release` into the header. The V15 rows on third-party components belong to 0017, which reads the advisory decision recorded in `mix.exs` and in `docs/security/key-management.md`.
