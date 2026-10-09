# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Accounts do
  @moduledoc """
  The Accounts context: users, sessions, invitations, e-mail and password
  changes, roles, machine clients and the administrative functions
  (README sections 6.2 to 6.5, 6.10 and 6.11).

  Lookups by address go through `email_hash` with `normalize_email/1`.
  Session tokens are 32 random bytes; the table stores their SHA-256 hash.
  A password alone never opens a session: every pathway ends in
  `create_session/2`, which checks the strength against the methods.
  """

  import Ecto.Query, warn: false

  alias Espalier.Accounts.{
    ApiClient,
    Demo,
    ExternalIdentity,
    Factors,
    FailureCounters,
    MailWorker,
    PasswordPolicy,
    RoleGrant,
    Scope,
    Totp,
    User,
    UserToken
  }

  alias Espalier.{Audit, RateLimit, Repo, SecurityLog}

  @factor_password %{factor: :password, provider: :local}

  ## Database getters

  @doc "Trims and lower-cases an address, the form of every write and lookup."
  defdelegate normalize_email(email), to: User

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email_hash: normalize_email(email))
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a single user, or `nil`."
  def get_user(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      :error -> nil
    end
  end

  @doc "True when the user holds an external identity."
  def external_identity?(%User{id: id}) do
    Repo.exists?(from i in ExternalIdentity, where: i.user_id == ^id)
  end

  @doc "True for an active account without an external identity, which excludes demo users."
  def local_account?(%User{status: :active} = user), do: not external_identity?(user)
  def local_account?(%User{}), do: false

  @doc """
  True when the user holds a local second factor: a passkey or a confirmed
  TOTP factor (`Espalier.Accounts.Factors`).
  """
  def enrolled?(%User{} = user), do: Factors.holds_passkey?(user) or Totp.enabled?(user)

  @doc """
  Sets a random 64-byte WebAuthn user handle when the user has none, and
  returns the reloaded user. The conditional update keeps one handle under
  concurrent requests; the handle holds no personal data.
  """
  def ensure_webauthn_user_handle(%User{} = user) do
    Repo.update_all(
      from(u in User, where: u.id == ^user.id and is_nil(u.webauthn_user_handle)),
      set: [webauthn_user_handle: :crypto.strong_rand_bytes(64)]
    )

    Repo.get!(User, user.id)
  end

  @doc """
  True for an active local user with an address, without an external
  identity and without an enrolled factor: the users an invitation may go to.
  """
  def invitable?(%User{status: :active, email: email} = user) when is_binary(email) do
    not external_identity?(user) and not enrolled?(user)
  end

  def invitable?(%User{}), do: false

  ## Password sign-in

  @doc """
  Verifies the password of an active, confirmed local account.

  Returns `{:ok, user}` or `{:error, :invalid_credentials}`. Unknown
  addresses, over-long passwords, accounts without a password and locked or
  disabled counters run a dummy verification and take the same time.
  `meta` carries `:ip` and an optional `:now`.
  """
  def authenticate_password(email, password, meta \\ %{})

  def authenticate_password(email, password, meta)
      when is_binary(email) and is_binary(password) do
    meta = Map.new(meta)
    now = Map.get(meta, :now, DateTime.utc_now())
    log = Map.put(@factor_password, :ip, meta[:ip])

    case get_local_user_by_email(email) do
      nil ->
        User.no_user_verify()

        fail(log, %{
          account_hash: RateLimit.account_hash(normalize_email(email)),
          reason: :unknown
        })

      user ->
        verify_password(user, password, now, Map.put(log, :user_id, user.id))
    end
  end

  def authenticate_password(_email, _password, _meta), do: {:error, :invalid_credentials}

  defp verify_password(user, password, now, log) do
    cond do
      PasswordPolicy.too_long?(password) ->
        User.no_user_verify()
        fail(log, %{reason: :too_long})

      is_nil(user.hashed_password) ->
        User.no_user_verify()
        fail(log, %{reason: :no_password})

      (status = FailureCounters.check(user, :password, now)) != :ok ->
        User.no_user_verify()
        fail(log, %{reason: lock_reason(status)})

      User.valid_password?(user, password) ->
        password_succeeded(user, log)

      true ->
        FailureCounters.record_failure(user, :password, now)
        fail(log, %{reason: :invalid})
    end
  end

  defp password_succeeded(user, log) do
    previous = FailureCounters.reset(user, :password)

    if previous >= 5 do
      Oban.insert!(
        MailWorker.job("failed_attempts", %{
          user_id: user.id,
          count: previous,
          factor: "password"
        })
      )

      SecurityLog.event(:authn_login_successafterfail, Map.put(log, :count, previous))
    end

    SecurityLog.event(:authn_login_success, Map.put(log, :reason, :second_factor_pending))
    {:ok, user}
  end

  defp lock_reason(:disabled), do: :disabled
  defp lock_reason({:locked, _until}), do: :locked

  defp fail(log, attrs) do
    SecurityLog.event(:authn_login_fail, Map.merge(log, attrs))
    {:error, :invalid_credentials}
  end

  defp get_local_user_by_email(email) do
    Repo.one(
      from u in User,
        as: :user,
        where: u.email_hash == ^normalize_email(email),
        where: u.status == :active and not is_nil(u.confirmed_at),
        where:
          not exists(
            from i in ExternalIdentity, where: i.user_id == parent_as(:user).id, select: 1
          )
    )
  end

  ## Sessions

  @doc """
  Creates a session row for `user` and returns `{token, session}`.

  `attrs` carries `:auth_methods`, `:strength`, and optionally `:mfa_at`,
  `:provider_key`, `:idp_sid_hash` (stored as given), `:device_summary`,
  `:replaces` (the raw token the cookie held before this sign-in) and `:now`.
  Raises `ArgumentError` unless `UserToken.strength_valid?/3` holds.

  Inside one transaction it deletes the replaced row, locks the user row,
  and deletes the oldest live sessions so that at most
  `SESSION_MAX_CONCURRENT` remain after the insert.
  """
  def create_session(%User{} = user, attrs) do
    attrs = Map.new(attrs)
    strength = Map.fetch!(attrs, :strength)
    methods = Map.fetch!(attrs, :auth_methods)

    if not UserToken.strength_valid?(strength, methods, attrs) do
      raise ArgumentError,
            "strength #{inspect(strength)} does not fit the methods #{inspect(methods)}"
    end

    now = attrs |> Map.get(:now, DateTime.utc_now()) |> DateTime.truncate(:second)
    {token, row} = UserToken.build_session_token(user, attrs, now)

    {:ok, session} =
      Repo.transact(fn ->
        delete_replaced_session(user, attrs[:replaces])
        lock_user!(user)
        trim_sessions(user, now)
        {:ok, Repo.insert!(row)}
      end)

    {token, session}
  end

  defp delete_replaced_session(_user, nil), do: :ok

  defp delete_replaced_session(user, token) when is_binary(token) do
    query =
      from t in UserToken.by_hash_and_context_query(UserToken.hash(token), :session),
        select: {t.id, t.user_id}

    case Repo.delete_all(query) do
      {1, [{id, user_id}]} when user_id == user.id ->
        SecurityLog.event(:session_renewed, %{user_id: user_id, session_id: id})

      {1, [{id, user_id}]} ->
        SecurityLog.event(:session_logout, %{user_id: user_id, session_id: id, reason: :replaced})

      {0, _} ->
        :ok
    end
  end

  defp trim_sessions(user, now) do
    keep = max(session_max_concurrent() - 1, 0)

    excess =
      Repo.all(
        from t in live_sessions_query(user.id, now),
          order_by: [desc: t.authenticated_at, desc: t.inserted_at, desc: t.id],
          offset: ^keep,
          select: t.id
      )

    if excess != [] do
      Repo.delete_all(from t in UserToken, where: t.id in ^excess)

      for id <- excess do
        SecurityLog.event(:excess_sessions_exceeded, %{user_id: user.id, session_id: id})
      end
    end

    :ok
  end

  defp live_sessions_query(user_id, now) do
    idle_since = DateTime.add(now, -session_idle_minutes(), :minute)

    from t in UserToken.user_sessions_query(user_id),
      where: t.expires_at > ^now and t.last_seen_at > ^idle_since
  end

  @doc """
  Returns `{:ok, user, session}` for the raw session token of an active
  user within both timeouts.

  A row that fails a timeout is deleted, logged as `session_expired` and
  answered with `{:error, :expired}`; a missing row is `{:error, :not_found}`.
  """
  def get_session_by_token(token, now \\ DateTime.utc_now())

  def get_session_by_token(token, now) when is_binary(token) do
    query =
      from t in UserToken.by_hash_and_context_query(UserToken.hash(token), :session),
        join: u in assoc(t, :user),
        select: {u, t}

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {user, session} -> check_session(user, session, now)
    end
  end

  def get_session_by_token(_token, _now), do: {:error, :not_found}

  defp check_session(user, session, now) do
    idle_since = DateTime.add(now, -session_idle_minutes(), :minute)

    cond do
      user.status != :active -> {:error, :not_found}
      not DateTime.after?(session.expires_at, now) -> expire_session(session, :absolute)
      not DateTime.after?(session.last_seen_at, idle_since) -> expire_session(session, :idle)
      true -> {:ok, user, session}
    end
  end

  defp expire_session(session, reason) do
    Repo.delete_all(from t in UserToken, where: t.id == ^session.id)

    SecurityLog.event(:session_expired, %{
      user_id: session.user_id,
      session_id: session.id,
      reason: reason
    })

    {:error, :expired}
  end

  @doc """
  Locks the row of the user until the end of the running transaction, which
  serializes the changes of one account: sessions, factors and recovery
  codes. Call it inside `Repo.transact/1`.
  """
  def lock_user!(%User{id: user_id}) do
    Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE", select: u.id)
  end

  @doc "Sets `last_login_at` of the user to now."
  def record_login(%User{} = user) do
    user |> Ecto.Changeset.change(last_login_at: DateTime.utc_now(:second)) |> Repo.update()
  end

  @doc """
  Updates `last_seen_at` of a session row when the stored value is older
  than one minute. Returns the session with the new value.
  """
  def touch_session(%UserToken{} = session, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    {count, _} =
      Repo.update_all(
        from(t in UserToken,
          where: t.id == ^session.id and t.last_seen_at < ^DateTime.add(now, -60, :second)
        ),
        set: [last_seen_at: now]
      )

    if count == 1, do: %{session | last_seen_at: now}, else: session
  end

  @doc """
  Replaces the session row of `token` by a copy with `changes` and a new
  token, in one transaction, and returns `{:ok, new_token}`.

  The copy keeps every column except `id`, `token_hash` and `inserted_at`,
  among them `expires_at` and the bytes of `idp_sid_hash`. It raises
  `ArgumentError` when a field of the type `Espalier.Hashed.HMAC` holds a
  value, because the copy would hash it a second time.
  """
  def reissue_session(token, changes \\ %{}) when is_binary(token) do
    Repo.transact(fn ->
      query =
        from t in UserToken.by_hash_and_context_query(UserToken.hash(token), :session),
          lock: "FOR UPDATE"

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        previous ->
          {new_token, row} = copy_session(previous, changes)
          Repo.delete!(previous)
          session = Repo.insert!(row)

          SecurityLog.event(:session_renewed, %{user_id: session.user_id, session_id: session.id})
          {:ok, new_token}
      end
    end)
  end

  @doc false
  # Builds an unsaved copy of a session row with a new token (reissue_session/2
  # and the password change).
  def copy_session(%UserToken{} = previous, changes) do
    fields = UserToken.__schema__(:fields)

    hmac_fields =
      Enum.filter(fields, &(UserToken.__schema__(:type, &1) == Espalier.Hashed.HMAC))

    if Enum.any?(hmac_fields, &(not is_nil(Map.fetch!(previous, &1)))) do
      raise ArgumentError, "a session row with a keyed-hash field value cannot be copied"
    end

    token = UserToken.generate()

    attrs =
      previous
      |> Map.take(fields -- [:id, :token_hash, :inserted_at])
      |> Map.merge(Map.new(changes))
      |> Map.put(:token_hash, UserToken.hash(token))

    {token, struct(UserToken, attrs)}
  end

  @doc """
  Deletes the session row of the raw token.
  """
  def delete_user_session_token(token) when is_binary(token) do
    Repo.delete_all(UserToken.by_hash_and_context_query(UserToken.hash(token), :session))
    :ok
  end

  @doc "Lists the live sessions of a user, newest first."
  def list_sessions(%User{id: user_id}, now \\ DateTime.utc_now()) do
    Repo.all(
      from t in live_sessions_query(user_id, now),
        order_by: [desc: t.authenticated_at, desc: t.inserted_at],
        select:
          map(t, [
            :id,
            :authenticated_at,
            :last_seen_at,
            :expires_at,
            :auth_methods,
            :strength,
            :device_summary
          ])
    )
  end

  @doc "Counts the live sessions of a user other than `session_id`."
  def count_other_sessions(%User{id: user_id}, session_id, now \\ DateTime.utc_now()) do
    Repo.aggregate(
      from(t in live_sessions_query(user_id, now), where: t.id != ^session_id),
      :count
    )
  end

  @doc "Deletes one session row of the user. Returns `:ok` or `{:error, :not_found}`."
  def delete_session(%User{id: user_id}, session_id) do
    with {:ok, id} <- Ecto.UUID.cast(session_id),
         {1, _} <-
           Repo.delete_all(from t in UserToken.user_sessions_query(user_id), where: t.id == ^id) do
      SecurityLog.event(:session_logout, %{user_id: user_id, session_id: id, reason: :user})
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  ## Invitations and sign-up

  @doc """
  Invites a new local user. Requires the role `admin`.

  `attrs` holds `email`, and optionally `display_name` (default: the local
  part of the address) and `locale`.
  """
  def invite_user(%Scope{} = scope, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    cond do
      not Scope.admin?(scope) ->
        {:error, :forbidden}

      is_binary(attrs["email"]) and get_user_by_email(attrs["email"]) != nil ->
        {:error, :user_exists}

      true ->
        Repo.transact(fn -> insert_invited_user(scope, attrs) end)
    end
  end

  defp insert_invited_user(scope, attrs) do
    with {:ok, user} <- %User{} |> User.invite_changeset(attrs) |> Repo.insert() do
      Oban.insert!(MailWorker.job("invitation", %{user_id: user.id}))
      {:ok, _event} = Audit.record(scope, "user.invited", user)
      SecurityLog.event(:user_created, %{user_id: user.id, reason: :invited})
      {:ok, user}
    end
  end

  @doc """
  Sends a new invitation to an invitable user (`invitable?/1`). Requires the
  role `admin`.
  """
  def resend_invitation(%Scope{} = scope, %User{} = user) do
    cond do
      not Scope.admin?(scope) ->
        {:error, :forbidden}

      invitable?(user) ->
        Oban.insert!(MailWorker.job("invitation", %{user_id: user.id}))
        {:ok, _event} = Audit.record(scope, "user.invitation_resent", user)
        :ok

      true ->
        {:error, :not_invitable}
    end
  end

  @doc """
  Handles `POST /api/auth/invitations` for `SIGNUP=invite` and
  `SIGNUP=domain`.

  Every request causes one lookup and one job insert: an invitation for an
  invitable user, a `signup` job for an unknown address of a listed domain
  with `SIGNUP=domain`, and the no-op job `none` in every other case. Known
  and unknown addresses therefore lead to the same database work and the
  same answer. Always returns `:ok`.
  """
  def request_invitation(email) when is_binary(email) do
    email = normalize_email(email)

    found =
      Repo.one(
        from u in User,
          as: :user,
          where: u.email_hash == ^email,
          select:
            {u,
             exists(
               from i in ExternalIdentity, where: i.user_id == parent_as(:user).id, select: 1
             )}
      )

    job =
      case found do
        {user, false} ->
          if user.status == :active and not enrolled?(user) and signup() in [:invite, :domain],
            do: MailWorker.job("invitation", %{user_id: user.id}),
            else: MailWorker.job("none")

        {_user, true} ->
          MailWorker.job("none")

        nil ->
          if signup() == :domain and signup_domain?(email),
            do: MailWorker.job("signup", %{email: MailWorker.encrypt_arg(email)}),
            else: MailWorker.job("none")
      end

    Oban.insert!(job)
    :ok
  end

  def request_invitation(_email), do: :ok

  defp signup, do: Application.get_env(:espalier, :signup, :closed)

  defp signup_domain?(email) do
    case String.split(email, "@", parts: 2) do
      [_local, domain] -> domain in Application.get_env(:espalier, :signup_domains, [])
      _ -> false
    end
  end

  @doc false
  # Creates the user of a `signup` job; skipped when the address has gained an
  # account in the meantime.
  def create_signup_user(email) do
    if get_user_by_email(email) do
      {:error, :user_exists}
    else
      Repo.transact(fn -> insert_signup_user(email) end)
    end
  end

  defp insert_signup_user(email) do
    with {:ok, user} <- %User{} |> User.invite_changeset(%{email: email}) |> Repo.insert() do
      {:ok, _event} = Audit.record(Scope.system(), "user.signed_up", user)
      SecurityLog.event(:user_created, %{user_id: user.id, reason: :signup})
      {:ok, user}
    end
  end

  @doc """
  Accepts an invitation token and returns `{:ok, user}`, or
  `{:error, :invalid_token}`.

  The token must belong to an active user, be at most 10 minutes old and
  have been sent to the user's current address. Users with an external
  identity or an enrolled factor are refused. Acceptance confirms the user
  and deletes every token row of the user, so the link works once.
  """
  def accept_invitation(token, now \\ DateTime.utc_now()) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, :invite, now),
         {user, _row} <-
           Repo.one(
             from [t, u] in query,
               where: t.sent_to_hash == u.email_hash and u.status == :active
           ),
         false <- external_identity?(user) or enrolled?(user) do
      confirm_invited_user(user)
    else
      _ -> {:error, :invalid_token}
    end
  end

  # Prevent session fixation attacks by disallowing invitations for
  # unconfirmed users with a password (pre-stuffing guard of phx.gen.auth).
  defp confirm_invited_user(%User{confirmed_at: nil, hashed_password: hash})
       when is_binary(hash) do
    raise "an invitation cannot be accepted for an unconfirmed user with a password set"
  end

  defp confirm_invited_user(user) do
    Repo.transact(fn ->
      user =
        if user.confirmed_at, do: user, else: user |> User.confirm_changeset() |> Repo.update!()

      Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
      {:ok, user}
    end)
  end

  ## E-mail change

  @doc """
  Requests a change of the address to `new_email`. When the address belongs
  to no account, the earlier change requests of the user are deleted and the
  mail goes out with a confirmation link; otherwise a no-op job is enqueued.
  Always returns `:ok`.
  """
  def request_email_change(%User{} = user, new_email) when is_binary(new_email) do
    new_email = normalize_email(new_email)
    taken? = Repo.exists?(from u in User, where: u.email_hash == ^new_email)

    if valid_email?(new_email) and not taken? do
      Repo.transact(fn ->
        Repo.delete_all(
          from t in UserToken, where: t.user_id == ^user.id and t.context == :change_email
        )

        Oban.insert!(
          MailWorker.job("change_email", %{
            user_id: user.id,
            email: MailWorker.encrypt_arg(new_email)
          })
        )

        {:ok, :requested}
      end)
    else
      Oban.insert!(MailWorker.job("none"))
    end

    :ok
  end

  def request_email_change(%User{}, _new_email), do: :ok

  defp valid_email?(email) do
    String.match?(email, ~r/^[^@,;\s]+@[^@,;\s]+$/) and String.length(email) <= 160
  end

  @doc """
  Confirms an e-mail change with the token of the signed-in user. Updates
  `email` and `email_hash`, deletes the user's change requests and tells
  the old address. Returns `{:ok, user}` or `{:error, :invalid_token}`.

  The generator binds the token to the old address; the port binds it to
  the account through `user_id`, because the address is encrypted.
  """
  def confirm_email_change(%User{} = user, token, now \\ DateTime.utc_now()) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, :change_email, now),
         {_user, %UserToken{new_email: new_email}} when is_binary(new_email) <-
           Repo.one(from [t, _u] in query, where: t.user_id == ^user.id),
         {:ok, updated} <- update_email(user, new_email) do
      SecurityLog.event(:user_updated, %{user_id: user.id, reason: :email_changed})
      {:ok, updated}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp update_email(user, new_email) do
    Repo.transact(fn -> write_email(user, new_email) end)
  end

  defp write_email(user, new_email) do
    with {:ok, updated} <- user |> User.email_changeset(%{email: new_email}) |> Repo.update() do
      Repo.delete_all(
        from t in UserToken, where: t.user_id == ^user.id and t.context == :change_email
      )

      if is_binary(user.email) do
        Oban.insert!(
          MailWorker.job("email_changed", %{
            user_id: user.id,
            email: MailWorker.encrypt_arg(user.email)
          })
        )
      end

      {:ok, updated}
    end
  end

  ## Password change

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Espalier.Accounts.User.password_changeset/3` for a list of supported options.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password and deletes every token row of the user in the
  same transaction. Returns `{:ok, {user, token}}`, where `token` is the raw
  token of the copied session (option `:keep_session`) or `nil`.

  ## Options

    * `:require_current` - requires and verifies `current_password` when the
      user has a password; a wrong value counts as a password failure.
      Defaults to `true`.
    * `:keep_session` - a session row of the user to copy with a new token
      after the deletion, so the calling client stays signed in.
  """
  def update_user_password(%User{} = user, attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    log = %{user_id: user.id, factor: :password, provider: :local}

    result =
      with :ok <- check_current_password(user, attrs, opts) do
        changeset = User.password_changeset(user, attrs)
        update_password_and_delete_tokens(changeset, opts[:keep_session])
      end

    case result do
      {:ok, _} ->
        Oban.insert!(MailWorker.job("password_changed", %{user_id: user.id}))
        SecurityLog.event(:authn_password_change, log)

      {:error, _} ->
        SecurityLog.event(:authn_password_change_fail, log)
    end

    result
  end

  defp check_current_password(user, attrs, opts) do
    if Keyword.get(opts, :require_current, true) and is_binary(user.hashed_password) do
      verify_current_password(user, attrs["current_password"])
    else
      :ok
    end
  end

  defp verify_current_password(user, current) when is_binary(current) and current != "" do
    now = DateTime.utc_now()

    cond do
      FailureCounters.check(user, :password, now) != :ok ->
        User.no_user_verify()
        current_password_error(user, :invalid)

      User.valid_password?(user, current) ->
        FailureCounters.reset(user, :password)
        :ok

      true ->
        FailureCounters.record_failure(user, :password, now)
        current_password_error(user, :invalid)
    end
  end

  defp verify_current_password(user, _current), do: current_password_error(user, :required)

  defp current_password_error(user, code) do
    message = if code == :required, do: "can't be blank", else: "is invalid"

    changeset =
      user
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:current_password, message, validation: code)

    {:error, changeset}
  end

  defp update_password_and_delete_tokens(changeset, keep_session) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
        {:ok, {user, insert_session_copy(user, keep_session)}}
      end
    end)
  end

  defp insert_session_copy(_user, nil), do: nil

  defp insert_session_copy(%User{id: user_id}, %UserToken{user_id: user_id} = session) do
    {token, row} = copy_session(session, %{})
    Repo.insert!(row)
    token
  end

  ## Roles

  @doc "Returns the role grants of the user."
  def list_role_grants(%User{id: user_id}) do
    Repo.all(from g in RoleGrant, where: g.user_id == ^user_id, order_by: [g.role, g.source])
  end

  @doc "Returns `[:learner | granted roles]` without duplicates."
  def roles_for(%User{} = user) do
    Enum.uniq([:learner | Enum.map(list_role_grants(user), & &1.role)])
  end

  @doc """
  Grants a `manual` role. Requires the role `admin`, writes the audit event
  `role.granted` and deletes every session row of the user, so the change
  leads to a new sign-in. Demo users receive no grant.
  """
  def grant_role(%Scope{} = scope, %User{} = user, role) do
    cond do
      not Scope.admin?(scope) ->
        {:error, :forbidden}

      demo_user?(user) ->
        {:error, :demo_user}

      grant = Repo.get_by(RoleGrant, user_id: user.id, role: role, source: :manual) ->
        {:ok, grant}

      true ->
        Repo.transact(fn -> insert_manual_grant(scope, user, role) end)
    end
  end

  defp insert_manual_grant(scope, user, role) do
    with {:ok, grant} <-
           %RoleGrant{}
           |> RoleGrant.changeset(%{role: role, source: :manual}, Scope.for_user(user))
           |> Repo.insert() do
      role_changed(scope, user, "role.granted", %{role: grant.role})
      {:ok, grant}
    end
  end

  @doc "Revokes a `manual` role, like `grant_role/3` with the audit event `role.revoked`."
  def revoke_role(%Scope{} = scope, %User{} = user, role) do
    if Scope.admin?(scope) do
      Repo.transact(fn -> delete_manual_grant(scope, user, role) end)
    else
      {:error, :forbidden}
    end
  end

  defp delete_manual_grant(scope, user, role) do
    query =
      from g in RoleGrant,
        where: g.user_id == ^user.id and g.role == ^role and g.source == :manual

    case Repo.delete_all(query) do
      {0, _} ->
        {:error, :not_found}

      {_count, _} ->
        role_changed(scope, user, "role.revoked", %{role: role})
        {:ok, role}
    end
  end

  @doc """
  Replaces the `idp_claim` grants of the user from `provider_key` with
  `roles`. Returns `{:ok, :unchanged}` when the set is equal; otherwise it
  replaces the grants, writes `role.synced`, deletes every session row of
  the user, and returns `{:ok, :changed}`. `manual` grants stay.
  """
  def replace_idp_role_grants(%User{} = user, provider_key, roles) do
    current =
      Repo.all(
        from g in RoleGrant,
          where: g.user_id == ^user.id and g.source == :idp_claim,
          select: g.role
      )
      |> MapSet.new()

    wanted = MapSet.new(roles)

    if MapSet.equal?(current, wanted) do
      {:ok, :unchanged}
    else
      Repo.transact(fn -> write_idp_grants(user, provider_key, current, wanted) end)
    end
  end

  defp write_idp_grants(user, provider_key, current, wanted) do
    Repo.delete_all(from g in RoleGrant, where: g.user_id == ^user.id and g.source == :idp_claim)

    for role <- wanted do
      %RoleGrant{}
      |> RoleGrant.changeset(
        %{role: role, source: :idp_claim, provider_key: provider_key},
        Scope.for_user(user)
      )
      |> Repo.insert!()
    end

    role_changed(Scope.system(), user, "role.synced", %{
      provider_key: provider_key,
      added: wanted |> MapSet.difference(current) |> Enum.sort(),
      removed: current |> MapSet.difference(wanted) |> Enum.sort()
    })

    {:ok, :changed}
  end

  defp role_changed(scope, user, action, details) do
    {:ok, _event} = Audit.record(scope, action, user, details)
    SecurityLog.event(:privilege_permissions_changed, %{user_id: user.id, reason: action})
    delete_all_sessions(user)
  end

  defp demo_user?(%User{id: id}) do
    Repo.exists?(
      from i in ExternalIdentity,
        where: i.user_id == ^id and i.provider_key == ^Demo.provider_key()
    )
  end

  defp delete_all_sessions(%User{id: user_id}) do
    {count, _} = Repo.delete_all(UserToken.user_sessions_query(user_id))
    count
  end

  ## Administration

  @doc "Disables the user and deletes every token row. Requires the role `admin`."
  def disable_user(%Scope{} = scope, %User{} = user) do
    with :ok <- require_admin(scope) do
      Repo.transact(fn ->
        user = user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()
        Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
        {:ok, _event} = Audit.record(scope, "user.disabled", user)
        SecurityLog.event(:user_updated, %{user_id: user.id, reason: :disabled})
        {:ok, user}
      end)
    end
  end

  @doc "Deletes every session row of the user. Requires the role `admin`."
  def end_user_sessions(%Scope{} = scope, %User{} = user) do
    with :ok <- require_admin(scope) do
      Repo.transact(fn ->
        count = delete_all_sessions(user)
        {:ok, _event} = Audit.record(scope, "sessions.ended", user, %{count: count})

        SecurityLog.event(:session_expired, %{user_id: user.id, reason: :admin, count: count})
        {:ok, count}
      end)
    end
  end

  @doc "Deletes every session row of every user. Requires the role `admin`."
  def end_all_sessions(%Scope{} = scope) do
    with :ok <- require_admin(scope) do
      Repo.transact(fn ->
        {count, _} = Repo.delete_all(from t in UserToken, where: t.context == :session)
        {:ok, _event} = Audit.record(scope, "sessions.ended_all", nil, %{count: count})
        SecurityLog.event(:session_expired, %{reason: :admin_all, count: count})
        {:ok, count}
      end)
    end
  end

  @doc """
  Creates a machine client with the scopes `["credentials:read"]` and
  returns `{:ok, {client, token}}`. The token is shown exactly once; the
  table stores its SHA-256 hash. Requires the role `admin`.
  """
  def create_api_client(%Scope{} = scope, attrs) do
    with :ok <- require_admin(scope) do
      Repo.transact(fn -> insert_api_client(scope, attrs) end)
    end
  end

  defp insert_api_client(scope, attrs) do
    bytes = UserToken.generate()

    with {:ok, client} <-
           %ApiClient{token_hash: UserToken.hash(bytes)}
           |> ApiClient.changeset(Map.new(attrs))
           |> Repo.insert() do
      {:ok, _event} = Audit.record(scope, "api_client.created", client, %{scopes: client.scopes})
      SecurityLog.event(:authn_token_created, %{reason: :api_client})
      {:ok, {client, Base.url_encode64(bytes, padding: false)}}
    end
  end

  @doc "Returns the machine client of a presented token, or `nil`."
  def get_api_client_by_token(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bytes} -> Repo.get_by(ApiClient, token_hash: UserToken.hash(bytes))
      :error -> nil
    end
  end

  def get_api_client_by_token(_token), do: nil

  @doc "Lists the machine clients. Requires the role `admin`."
  def list_api_clients(%Scope{} = scope) do
    with :ok <- require_admin(scope) do
      {:ok, Repo.all(from c in ApiClient, order_by: [c.name, c.inserted_at])}
    end
  end

  @doc "Deletes a machine client. Requires the role `admin`."
  def delete_api_client(%Scope{} = scope, %ApiClient{} = client) do
    with :ok <- require_admin(scope) do
      Repo.transact(fn ->
        client = Repo.delete!(client)
        {:ok, _event} = Audit.record(scope, "api_client.deleted", client)
        SecurityLog.event(:authn_token_revoked, %{reason: :api_client})
        {:ok, client}
      end)
    end
  end

  defp require_admin(scope) do
    if Scope.admin?(scope), do: :ok, else: {:error, :forbidden}
  end

  ## Settings

  defp session_idle_minutes, do: Application.get_env(:espalier, :session_idle_minutes, 60)
  defp session_max_concurrent, do: Application.get_env(:espalier, :session_max_concurrent, 5)
end
