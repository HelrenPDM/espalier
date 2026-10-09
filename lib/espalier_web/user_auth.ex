# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule EspalierWeb.UserAuth do
  @moduledoc """
  Session handling and authorization plugs of the JSON API
  (README sections 6.2, 6.5 and 6.12).

  The Plug session of every `/api` route is the cookie `__Host-espalier`. It
  holds `user_token` after sign-in, `_csrf_token`, during sign-in
  `pending_second_factor` with `pending_second_factor_failures`, and the
  id of a running WebAuthn ceremony under `webauthn_ceremony`. Every pathway ends in `log_in_user/3`, which
  creates the session row with its methods and strength, deletes the row the
  cookie held before, renews the session and rotates the CSRF token.

  Every 403 of these plugs logs `authz_fail` with the reason.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Espalier.Accounts
  alias Espalier.Accounts.{DeviceSummary, Scope, UserToken}
  alias Espalier.SecurityLog

  @pending_key :pending_second_factor
  @pending_seconds 300

  @doc """
  Logs the user in with the attributes of `Accounts.create_session/2`
  (`auth_methods:`, `strength:`, and optionally `mfa_at:`, `provider_key:`,
  `idp_sid_hash:`, `idp_amr:`). The security events carry `provider:`, which defaults
  to the `provider_key` or `local`.

  Returns the conn; the controller renders the session payload, which
  carries the new CSRF token.
  """
  def log_in_user(conn, user, attrs) do
    attrs = Map.new(attrs)
    {provider, attrs} = Map.pop(attrs, :provider, attrs[:provider_key] || :local)

    {token, session} =
      Accounts.create_session(
        user,
        attrs
        |> Map.put(:replaces, get_session(conn, :user_token))
        |> Map.put(:device_summary, DeviceSummary.from_user_agent(user_agent(conn)))
      )

    {:ok, user} = Accounts.record_login(user)

    log = %{user_id: user.id, session_id: session.id, ip: conn.remote_ip, provider: provider}
    SecurityLog.event(:session_created, log)

    SecurityLog.event(
      :authn_login_success,
      Map.put(log, :factor, Enum.map_join(session.auth_methods, "+", &Atom.to_string/1))
    )

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> assign(:current_scope, Scope.for_session(user, session, Accounts.list_role_grants(user)))
  end

  @doc """
  Puts the token of a reissued or copied session row into a renewed
  session, which rotates the CSRF token, and assigns its scope.
  """
  def put_reissued_session(conn, token) when is_binary(token) do
    {:ok, user, session} = Accounts.get_session_by_token(token)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> assign(:current_scope, Scope.for_session(user, session, Accounts.list_role_grants(user)))
  end

  @doc """
  Replaces the session by the pending second-factor state of `user` after
  a first factor. `attrs` carries `auth_methods:`, and optionally
  `provider_key:` and `idp_sid_hash:` (bytes, stored Base64-encoded). The
  state expires after five minutes.
  """
  def put_pending_second_factor(conn, user, attrs) do
    attrs = Map.new(attrs)
    conn = drop_session_row(conn, :pending_second_factor)

    pending = %{
      "user_id" => user.id,
      "auth_methods" => Enum.map(Map.fetch!(attrs, :auth_methods), &Atom.to_string/1),
      "provider_key" => attrs[:provider_key],
      "idp_sid_hash" => attrs[:idp_sid_hash] && Base.encode64(attrs[:idp_sid_hash]),
      "expires_at" => System.os_time(:second) + @pending_seconds
    }

    conn
    |> renew_session()
    |> put_session(@pending_key, pending)
  end

  @doc """
  Returns `{:ok, pending}` with the loaded user, the methods as atoms and
  `idp_sid_hash` decoded to its bytes, or `:error` for a missing or expired
  state. `fetch_current_scope_for_user/2` deletes an expired state.
  """
  def fetch_pending_second_factor(conn) do
    with %{"user_id" => user_id, "expires_at" => expires_at} = pending <-
           get_session(conn, @pending_key),
         true <- expires_at > System.os_time(:second),
         %Accounts.User{status: :active} = user <- Accounts.get_user(user_id) do
      {:ok,
       %{
         user: user,
         auth_methods: Enum.map(pending["auth_methods"], &UserToken.method!/1),
         provider_key: pending["provider_key"],
         idp_sid_hash: pending["idp_sid_hash"] && Base.decode64!(pending["idp_sid_hash"]),
         expires_at: DateTime.from_unix!(expires_at)
       }}
    else
      _ -> :error
    end
  end

  @doc """
  Logs the user out: deletes the session row and renews the session.
  """
  def log_out_user(conn) do
    conn
    |> drop_session_row(:user)
    |> renew_session()
    |> assign(:current_scope, nil)
  end

  defp drop_session_row(conn, reason) do
    with token when is_binary(token) <- get_session(conn, :user_token) do
      case Accounts.get_session_by_token(token) do
        {:ok, user, session} ->
          SecurityLog.event(:session_logout, %{
            user_id: user.id,
            session_id: session.id,
            ip: conn.remote_ip,
            reason: reason
          })

        {:error, _reason} ->
          :ok
      end

      Accounts.delete_user_session_token(token)
    end

    conn
  end

  # This function renews the session ID and erases the whole session to avoid
  # fixation attacks. It runs at every sign-in and sign-out, also for the same
  # user, and rotates the CSRF token.
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp user_agent(conn), do: conn |> get_req_header("user-agent") |> List.first()

  @doc """
  Authenticates the user by the session token, checks both timeouts on the
  server, updates `last_seen_at` and assigns `current_scope`.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    conn = drop_expired_pending(conn)

    with token when is_binary(token) <- get_session(conn, :user_token),
         {:ok, user, session} <- Accounts.get_session_by_token(token) do
      session = Accounts.touch_session(session)

      assign(
        conn,
        :current_scope,
        Scope.for_session(user, session, Accounts.list_role_grants(user))
      )
    else
      nil ->
        assign(conn, :current_scope, nil)

      {:error, _reason} ->
        conn
        |> delete_session(:user_token)
        |> assign(:current_scope, nil)
    end
  end

  defp drop_expired_pending(conn) do
    case get_session(conn, @pending_key) do
      %{"expires_at" => expires_at} when is_integer(expires_at) ->
        if expires_at > System.os_time(:second),
          do: conn,
          else: delete_session(conn, @pending_key)

      nil ->
        conn

      _invalid ->
        delete_session(conn, @pending_key)
    end
  end

  @doc """
  Passes sessions of the strengths `mfa` and `demo`. Without a session it
  answers 401 `unauthenticated`; enrollment and recovery sessions receive
  403 `enrollment_required`.
  """
  def require_authenticated_user(conn, _opts) do
    case strength(conn) do
      strength when strength in [:mfa, :demo] -> conn
      nil -> unauthenticated(conn)
      _limited -> deny(conn, "enrollment_required")
    end
  end

  @doc """
  Passes sessions of the strengths `enrollment`, `recovery` and `mfa`. A demo
  session receives 403 `forbidden`.
  """
  def require_enrollment_session(conn, _opts) do
    case strength(conn) do
      strength when strength in [:enrollment, :recovery, :mfa] -> conn
      nil -> unauthenticated(conn)
      _other -> deny(conn, "forbidden")
    end
  end

  @doc """
  Answers 403 `reauth_required` unless the session recorded a second factor
  within the last 10 minutes (port of `require_sudo_mode/2`). Enrollment and
  recovery sessions pass: they reach only the routes of the `:enrollment`
  pipeline, which every route of this plug also runs.
  """
  def require_recent_auth(conn, _opts) do
    if strength(conn) in [:enrollment, :recovery] or
         Scope.recent_auth?(conn.assigns[:current_scope]) do
      conn
    else
      deny(conn, "reauth_required")
    end
  end

  @doc """
  Records a second factor `method` on the current session: the session row
  is reissued with `mfa_at` now and `method` appended to `auth_methods`,
  and the previous row is deleted in the same transaction. The copy keeps
  every other column, among them `expires_at`, `provider_key` and the
  bytes of `idp_sid_hash`. `changes` are merged into the changes of the
  reissue, such as `idp_amr` after a step-up at the provider (task 0006).
  Returns `{:ok, conn}` with a renewed session and CSRF token, or
  `{:error, :not_found}`.
  """
  def step_up(conn, method, changes \\ %{}) do
    %Scope{session: session} = conn.assigns.current_scope

    methods =
      if method in session.auth_methods,
        do: session.auth_methods,
        else: session.auth_methods ++ [method]

    with token when is_binary(token) <- get_session(conn, :user_token),
         {:ok, new_token} <-
           Accounts.reissue_session(
             token,
             Map.merge(
               %{mfa_at: DateTime.utc_now(:second), auth_methods: methods},
               Map.new(changes)
             )
           ) do
      {:ok, put_reissued_session(conn, new_token)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Answers 403 `forbidden` unless the scope holds `role`."
  def require_role(conn, role) when is_atom(role) do
    if Scope.has_role?(conn.assigns[:current_scope], role) do
      conn
    else
      deny(conn, "forbidden")
    end
  end

  @doc """
  Checks the CSRF token of `Plug.CSRFProtection` from the `x-csrf-token`
  header on every mutating request, and answers 403 `csrf` otherwise.
  """
  def protect_api_from_forgery(conn, _opts) do
    if conn.method not in ~w(GET HEAD OPTIONS) and get_req_header(conn, "x-csrf-token") == [] do
      csrf_failed(conn)
    else
      protect_from_forgery(conn, [])
    end
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError -> csrf_failed(conn)
  end

  defp csrf_failed(conn) do
    SecurityLog.event(:malicious_csrf, %{ip: conn.remote_ip, user_id: current_user_id(conn)})

    conn
    |> put_status(:forbidden)
    |> json(%{error: "csrf"})
    |> halt()
  end

  defp strength(conn) do
    case conn.assigns[:current_scope] do
      %Scope{session: %UserToken{strength: strength}} -> strength
      _ -> nil
    end
  end

  defp current_user_id(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %{id: id}} -> id
      _ -> nil
    end
  end

  defp unauthenticated(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthenticated"})
    |> halt()
  end

  defp deny(conn, code) do
    SecurityLog.event(:authz_fail, %{
      user_id: current_user_id(conn),
      ip: conn.remote_ip,
      reason: code
    })

    conn
    |> put_status(:forbidden)
    |> json(%{error: code})
    |> halt()
  end
end
