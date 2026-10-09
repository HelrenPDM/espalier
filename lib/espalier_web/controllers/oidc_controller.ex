defmodule EspalierWeb.OidcController do
  @moduledoc """
  The browser legs of an OIDC sign-in (task 0006, steps 9, 10 and 13;
  README section 6.7). The routes run in the `:oidc_transaction` pipeline,
  whose Plug session is the transaction cookie `__Host-espalier_tx`.

  - `authorize/2` stores the transaction, lets `Oidcc.Plug.Authorize` build
    the authorization request with PKCE S256, `state` and `nonce`, and
    redirects to the provider.
  - `callback/2` checks the transaction and the provider, lets
    `Oidcc.Plug.AuthorizationCallback` redeem the code and validate the ID
    token, applies the provider rules, and redirects to
    `/auth/finish#ticket=<ticket>`. It creates no session: the session
    starts at `POST /api/auth/finish` (ASVS 7.6.2).
  - `front_channel_logout/2` ends the sessions of a provider `sid`.

  Every failure logs `authn_login_fail` with `provider`, `purpose` and the
  reason tag and redirects to `/auth/finish?error=<code>`. A callback failure
  drops the transaction only after the response's `state` matched it, so a
  forged callback leaves a sign-in in progress intact. No error term of oidcc reaches the log, only
  its reason tag (ASVS 16.2.5).
  """
  use EspalierWeb, :controller

  alias Espalier.{Accounts, Identity, SecurityLog}
  alias Espalier.Accounts.UserToken
  alias Espalier.Identity.Oidc
  alias Espalier.Identity.Oidc.Rules
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.TransactionCookie
  alias Oidcc.Plug.{AuthorizationCallback, Authorize}

  # A provider whose worker lost its configuration after the check of the
  # action; transport errors of Espalier.Identity.Oidc.HttpAdapter count as
  # unreachable as well (callback_result/2).
  @unreachable [:provider_not_ready]

  plug RateLimit, [bucket: :oidc_authorize] when action in [:authorize]
  plug RateLimit, [bucket: :oidc_callback] when action in [:callback]
  plug RateLimit, [bucket: :oidc_front_channel] when action in [:front_channel_logout]

  ## Authorize

  def authorize(conn, %{"provider" => key} = params) do
    case Identity.fetch_oidc_provider(key) do
      {:ok, provider} -> start_flow(conn, provider, params)
      :error -> unknown_provider(conn)
    end
  end

  defp start_flow(conn, provider, params) do
    with {:ok, purpose, user_id} <- resolve_purpose(conn, provider, params),
         {:ok, _configuration} <- configuration(provider, purpose) do
      redirect_to_provider(conn, provider, purpose, user_id)
    else
      {:error, purpose, reason, code} -> fail(conn, provider, purpose, reason, code)
    end
  end

  # Without an intent the purpose is sign_in. An intent works once, only
  # with a live mfa session, and only in the session row that created it.
  defp resolve_purpose(conn, provider, params) do
    case Map.fetch(params, "intent") do
      :error -> {:ok, "sign_in", nil}
      {:ok, intent} -> consume_intent(conn, provider, intent)
    end
  end

  defp consume_intent(conn, provider, intent) do
    session = live_main_session(conn)

    case Accounts.consume_oidc_intent(intent, provider.key, session && session.id) do
      {:ok, %{user_id: user_id, purpose: purpose}} ->
        if session.strength == :mfa and session.user_id == user_id,
          do: {:ok, purpose, user_id},
          else: {:error, purpose, :intent_session_mismatch, "oidc_failed"}

      {:error, :session_mismatch} ->
        {:error, nil, :intent_session_mismatch, "oidc_failed"}

      {:error, :invalid} ->
        {:error, nil, :intent_invalid, "oidc_failed"}
    end
  end

  defp live_main_session(conn) do
    with %{"user_token" => token} when is_binary(token) <-
           TransactionCookie.read_main_session(conn),
         {:ok, _user, %UserToken{} = session} <- Accounts.get_session_by_token(token) do
      session
    else
      _ -> nil
    end
  end

  # Every redirect to the provider, which oidcc can precede with a pushed
  # authorization request, passes the host allowlist first.
  defp configuration(provider, purpose) do
    with {:ok, configuration} <- ready(provider, purpose),
         :ok <- endpoints_allowed(provider, configuration, purpose) do
      {:ok, configuration}
    end
  end

  defp ready(provider, purpose) do
    case Oidc.provider_configuration(provider) do
      {:ok, configuration} -> {:ok, configuration}
      {:error, :provider_not_ready} -> {:error, purpose, :provider_not_ready, "oidc_unavailable"}
    end
  end

  defp endpoints_allowed(provider, configuration, purpose) do
    case Oidc.check_endpoints(provider, configuration) do
      :ok -> :ok
      {:error, reason} -> {:error, purpose, reason, "oidc_unavailable"}
    end
  end

  defp redirect_to_provider(conn, provider, purpose, user_id) do
    conn =
      conn
      |> clear_session()
      |> put_session("oidc", %{
        "provider_key" => provider.key,
        "purpose" => purpose,
        "user_id" => user_id,
        "requested_at" => System.os_time(:second)
      })

    # Authorize relays a `state` request parameter; no request parameter
    # takes part in the flow.
    conn
    |> Map.update!(:params, &Map.delete(&1, "state"))
    |> Authorize.call(Authorize.init(authorize_opts(provider, purpose)))
  rescue
    error in Authorize.Error ->
      fail(conn, provider, purpose, Oidc.reason_tag(error.reason), "oidc_unavailable")
  catch
    # oidcc reads the worker through a call, which exits while the worker
    # waits for a slow provider.
    :exit, _reason -> fail(conn, provider, purpose, :provider_not_ready, "oidc_unavailable")
  end

  @doc false
  # The options of Oidcc.Plug.Authorize (task 0006, step 9).
  def authorize_opts(provider, purpose) do
    [
      provider: provider.worker,
      client_id: provider.client_id,
      client_secret: Oidc.client_secret(provider),
      client_context_opts: Oidc.client_context_opts(provider),
      client_profile_opts: %{profiles: [], require_pkce: true, trusted_audiences: []},
      redirect_uri: provider.redirect_uri,
      scopes: ["openid", "profile", "email"],
      require_pkce: true,
      response_mode: "query",
      url_extension: if(purpose == "step_up", do: [{"max_age", "0"}], else: []),
      request_opts: Oidc.request_opts()
    ]
  end

  ## Callback

  def callback(conn, %{"provider" => key} = params) do
    case Identity.fetch_oidc_provider(key) do
      {:ok, provider} -> finish_flow(conn, provider, params)
      :error -> unknown_provider(conn)
    end
  end

  # Until the response is bound to the transaction of this browser, a failure
  # keeps the transaction cookie: a forged cross-site request to the callback,
  # with or without `error`, cannot end a sign-in in progress. Every later
  # failure drops it.
  defp finish_flow(conn, provider, params) do
    tx = get_session(conn, "oidc")
    purpose = if is_map(tx), do: tx["purpose"]

    with {:ok, configuration} <- configuration(provider, purpose),
         :ok <- check_bound(conn, tx, params, purpose) do
      finish_bound(conn, provider, params, tx, configuration)
    else
      {:error, purpose, reason, code} ->
        fail(conn, provider, purpose, reason, code, keep_transaction: true)
    end
  end

  defp finish_bound(conn, provider, params, tx, configuration) do
    purpose = tx["purpose"]

    with :ok <- check_provider(tx, provider, purpose),
         :ok <- provider_error(params, purpose),
         :ok <- check_iss(params, provider, configuration, purpose),
         {:ok, conn, id_token, claims} <- redeem_code(conn, provider, purpose),
         {:ok, assertion} <- rules(provider, id_token, claims, tx),
         {:ok, ticket_attrs} <- by_purpose(provider, assertion, tx) do
      issue_ticket(conn, provider, assertion, ticket_attrs)
    else
      {:error, purpose, reason, code} -> fail(conn, provider, purpose, reason, code)
    end
  end

  defp check_bound(conn, tx, params, purpose) do
    cond do
      not (is_map(tx) and is_binary(tx["provider_key"])) ->
        {:error, purpose, :missing_transaction, "oidc_failed"}

      not state_verified?(conn, params) ->
        {:error, purpose, :state_not_verified, "oidc_failed"}

      true ->
        :ok
    end
  end

  # Oidcc.Plug.Authorize keeps :erlang.phash2/1 of the state it sent in its
  # session entry, and AuthorizationCallback compares it the same way. The
  # check runs here first, because the plug deletes its entry on every call.
  defp state_verified?(conn, %{"state" => state}) when is_binary(state) do
    case get_session(conn, Authorize.get_session_name()) do
      %{state_verifier: verifier} -> :erlang.phash2(state) == verifier
      _missing -> false
    end
  end

  defp state_verified?(_conn, _params), do: false

  # The provider key of the transaction must equal the path segment: a
  # response that arrives at another provider's redirect URI ends before any
  # token request (RFC 9700, section 4.4.2.2).
  defp check_provider(%{"provider_key" => key}, %{key: key}, _purpose), do: :ok

  defp check_provider(_tx, _provider, purpose),
    do: {:error, purpose, :provider_mismatch, "oidc_failed"}

  defp provider_error(%{"error" => "access_denied"}, purpose),
    do: {:error, purpose, :access_denied, "oidc_cancelled"}

  defp provider_error(%{"error" => _error}, purpose),
    do: {:error, purpose, :provider_error, "oidc_failed"}

  defp provider_error(_params, _purpose), do: :ok

  # RFC 9207: a provider that advertises the iss parameter must send it.
  defp check_iss(params, provider, configuration, purpose) do
    if configuration.authorization_response_iss_parameter_supported == true and
         params["iss"] != provider.issuer,
       do: {:error, purpose, :issuer_mismatch, "oidc_failed"},
       else: :ok
  end

  # The access and refresh tokens of the result are dropped here.
  defp redeem_code(conn, provider, purpose) do
    case run_callback_plug(conn, provider) do
      {:ok, conn} -> callback_result(conn, purpose)
      {:error, _exception} -> {:error, purpose, :invalid_callback, "oidc_failed"}
      :exit -> {:error, purpose, :provider_not_ready, "oidc_unavailable"}
    end
  end

  # oidcc reads the worker through a call, which exits while the worker waits
  # for a slow provider. oidcc_plug raises for some malformed request
  # parameters, such as a `scope` that is no string.
  defp run_callback_plug(conn, provider) do
    {:ok, AuthorizationCallback.call(conn, AuthorizationCallback.init(callback_opts(provider)))}
  rescue
    error -> {:error, error.__struct__}
  catch
    :exit, _reason -> :exit
  end

  defp unreachable?(%Req.TransportError{}, _tag), do: true
  defp unreachable?(_reason, tag), do: tag in @unreachable

  defp callback_result(conn, purpose) do
    case conn.private[AuthorizationCallback] do
      {:ok, {%Oidcc.Token{id: %Oidcc.Token.Id{token: id_token, claims: claims}}, _userinfo}} ->
        {:ok, conn, id_token, claims}

      {:error, reason} ->
        tag = Oidc.reason_tag(reason)
        code = if unreachable?(reason, tag), do: "oidc_unavailable", else: "oidc_failed"
        {:error, purpose, tag, code}

      _other ->
        {:error, purpose, :token_invalid, "oidc_failed"}
    end
  end

  @doc false
  # The options of Oidcc.Plug.AuthorizationCallback (task 0006, step 10).
  def callback_opts(provider) do
    [
      provider: provider.worker,
      client_id: provider.client_id,
      client_secret: Oidc.client_secret(provider),
      client_context_opts: Oidc.client_context_opts(provider),
      client_profile_opts: %{profiles: [], require_pkce: true, trusted_audiences: []},
      redirect_uri: provider.redirect_uri,
      preferred_auth_methods: Oidc.auth_methods(provider),
      retrieve_userinfo: false,
      check_peer_ip: true,
      check_useragent: true,
      request_opts: Oidc.request_opts()
    ]
  end

  defp rules(provider, id_token, claims, tx) do
    case Rules.check(provider, id_token, claims, tx) do
      {:ok, assertion} -> {:ok, assertion}
      {:error, reason} -> {:error, tx["purpose"], reason, "oidc_failed"}
    end
  end

  defp by_purpose(provider, assertion, %{"purpose" => "sign_in"}) do
    case Accounts.sign_in_external(provider, assertion) do
      {:ok, user} ->
        methods = if Rules.idp_mfa?(provider, assertion), do: [:oidc, :idp_mfa], else: [:oidc]
        {:ok, %{user_id: user.id, purpose: "sign_in", auth_methods: methods}}

      {:error, :no_account} ->
        {:error, "sign_in", :no_account, "oidc_no_account"}

      {:error, reason} ->
        {:error, "sign_in", reason, "oidc_failed"}
    end
  end

  # The callback writes no identity; the finish step links it in the
  # browser session that started the flow.
  defp by_purpose(provider, assertion, %{"purpose" => "link", "user_id" => user_id}) do
    case Accounts.check_external_link(user_id, provider, assertion) do
      result when result in [:ok, {:ok, :already_linked}] ->
        {:ok,
         %{
           user_id: user_id,
           purpose: "link",
           auth_methods: [:oidc],
           link_identity: assertion
         }}

      {:error, :identity_in_use} ->
        {:error, "link", :identity_in_use, "oidc_identity_in_use"}

      {:error, reason} ->
        {:error, "link", reason, "oidc_failed"}
    end
  end

  defp by_purpose(provider, assertion, %{"purpose" => "step_up", "user_id" => user_id}) do
    with :ok <- Accounts.check_external_step_up(user_id, provider, assertion),
         true <- Rules.idp_mfa?(provider, assertion) || {:error, :amr_single_factor} do
      {:ok, %{user_id: user_id, purpose: "step_up", auth_methods: [:oidc, :idp_mfa]}}
    else
      {:error, reason} -> {:error, "step_up", reason, "oidc_failed"}
    end
  end

  defp by_purpose(_provider, _assertion, tx),
    do: {:error, tx["purpose"], :missing_transaction, "oidc_failed"}

  # The fragment keeps the ticket out of server logs and the Referer header.
  # The transaction cookie carries the binding until the finish step.
  defp issue_ticket(conn, provider, assertion, attrs) do
    {ticket, binding} =
      attrs
      |> Map.merge(%{
        provider_key: provider.key,
        idp_amr: assertion.amr,
        idp_sid_hash: UserToken.hash_idp_sid(assertion.sid)
      })
      |> Accounts.create_login_ticket()

    conn
    |> clear_session()
    |> put_session("ticket_binding", binding)
    |> redirect(to: "/auth/finish#ticket=" <> ticket)
  end

  ## Front-channel logout

  @doc """
  Ends every session of the provider whose `idp_sid_hash` matches `sid`.
  Entra ID loads this URL in an iframe; the request carries no platform
  cookie, and the action reads and writes no session. A present `iss` must
  equal the provider's issuer. The answer is always 200 with an empty body.
  """
  def front_channel_logout(conn, %{"provider" => key} = params) do
    case Identity.fetch_oidc_provider(key) do
      {:ok, provider} ->
        if Map.get(params, "iss", provider.issuer) == provider.issuer do
          end_sessions(provider, params["sid"])
        end

        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, "")

      :error ->
        unknown_provider(conn)
    end
  end

  defp end_sessions(provider, sid) when is_binary(sid) and sid != "" do
    count = Accounts.delete_sessions_by_idp_sid(provider.key, sid)

    SecurityLog.event(:session_logout, %{
      provider: provider.key,
      trigger: "front_channel",
      count: count
    })
  end

  defp end_sessions(_provider, _sid), do: :ok

  ## Helpers

  defp fail(conn, provider, purpose, reason, code, opts \\ []) do
    SecurityLog.event(:authn_login_fail, %{
      provider: provider.key,
      purpose: purpose,
      reason: reason,
      ip: conn.remote_ip
    })

    conn =
      if Keyword.get(opts, :keep_transaction, false),
        do: conn,
        else: configure_session(conn, drop: true)

    redirect(conn, to: "/auth/finish?error=" <> code)
  end

  defp unknown_provider(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "unknown_provider"})
  end
end
