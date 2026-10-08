This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

## Project rules

- Run every toolchain command (`mix`, `npm`, `node`, `plantuml`, `gitleaks`) through `make` or `nix-shell --run`, never with a globally installed tool
- Create code with `mix phx.gen.*` (and the other standard generators) before editing it by hand
- Keep secrets and organization names out of the repository; configuration comes from environment variables, and `.env.example` holds placeholders only
- The implementation plan and the task specs live in `docs/plan/`
- Update the diagrams in `docs/architecture/` in the same change as the code they describe

### Encrypted and hashed data

- A column with personal data or an authenticator secret has the column type `:binary` and one of the Ecto types `Espalier.Encrypted.Binary`, `Espalier.Encrypted.Map` or `Espalier.Encrypted.ClosureBinary`, with `redact: true`. A column for lookups by such a value has the type `Espalier.Hashed.HMAC`, with `redact: true`, and the changeset fills it from the normalized plaintext
- A keyed hash that is copied from one row into another, or carried through the session or a sign-in ticket, has a plain `:binary` field with `redact: true`. Its value comes once from `Espalier.Hashed.HMAC.hash/1` of the normalized plaintext, every copy takes the stored bytes unchanged, and every lookup compares with `hash/1` of the presented value. The Ecto type `Espalier.Hashed.HMAC` hashes every value it dumps, so a loaded hash written through it is hashed a second time and matches no lookup
- No encrypted or hashed type appears inside `embedded_schema`, `embeds_one` or `embeds_many`. Structured personal data goes into one `Espalier.Encrypted.Map` column
- Every table with an encrypted column gets a rotation-only schema `Espalier.Crypto.Rotation.<Table>` in `lib/espalier/crypto/rotation/<table>.ex`, registered in `Espalier.Crypto.Rotation.schemas/0`, and every encrypted, hashed or password-hash column gets a row in `docs/security/crypto-inventory.md`, both in the same change
- A value encrypted with `Espalier.Vault.encrypt!/1` outside an Ecto type, such as an address in Oban job arguments, gets a row in the section "Values encrypted outside Ecto types" of `docs/security/crypto-inventory.md` with its location and its lifetime in the same change. `rotate_encryption/0` does not rewrite such values, so the rotation runbook waits until no value under the old tag is still read
- Only `lib/espalier/vault.ex`, `lib/espalier/crypto/`, `lib/espalier/encrypted/` and `lib/espalier/hashed/` call Cloak
- Repo calls take no `log:` option, and a telemetry handler for Repo events calls `Espalier.Telemetry.QueryLog.scrub/1` first
- A data migration that writes an encrypted field calls `Espalier.Vault.start_link()` first, because `mix ecto.migrate` and `bin/migrate` do not start the application


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- usage-rules-end -->