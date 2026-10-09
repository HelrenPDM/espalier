defmodule EspalierWeb.Auth.FinishController do
  @moduledoc """
  `POST /api/auth/finish` with `{"ticket": ...}`: the same-origin end of an
  OIDC flow (task 0006, step 12; README section 6.12).

  The ticket works once, for 60 seconds, and only together with the binding
  that the callback stored in the transaction cookie of the browser that
  started the flow (ASVS 2.3.1, 10.1.2). Every answer deletes the
  transaction cookie.

  - `sign_in` ends in `UserAuth.log_in_user/3` or
    `UserAuth.put_pending_second_factor/3`: a full session after the
    provider's MFA in `idp_trusted` mode, `{"next": "second_factor"}` for
    an enrolled user, or an enrollment session with
    `{"next": "enroll_second_factor"}`.
  - `link` links the identity to the account of the current session, which
    must be the account that created the intent.
  - `step_up` reissues the current session with `idp_mfa` and `mfa_at` now.
  """
  use EspalierWeb, :controller

  alias Espalier.{Accounts, Identity, SecurityLog}
  alias Espalier.Accounts.Scope
  alias EspalierWeb.{FallbackController, SessionController, TransactionCookie, UserAuth}
  alias EspalierWeb.Plugs.RateLimit

  plug :take_ticket_binding
  plug RateLimit, [bucket: :auth_ip] when action in [:create]

  def create(conn, params) do
    case Accounts.consume_login_ticket(params["ticket"], conn.assigns.ticket_binding) do
      {:ok, ticket} -> finish(conn, ticket)
      {:error, :invalid} -> reject(conn, nil, nil, :ticket_invalid)
    end
  end

  # The binding is read before the cookie is deleted; every answer of this
  # route deletes the transaction cookie.
  defp take_ticket_binding(conn, _opts) do
    binding = TransactionCookie.get(conn, "ticket_binding")

    conn
    |> assign(:ticket_binding, binding)
    |> TransactionCookie.clear()
  end

  defp finish(conn, %{purpose: "sign_in"} = ticket) do
    case Accounts.get_user(ticket.user_id) do
      %Accounts.User{status: :active} = user -> sign_in(conn, user, ticket)
      _ -> reject(conn, ticket, "sign_in", :account_disabled)
    end
  end

  defp finish(conn, %{purpose: purpose} = ticket) when purpose in ["link", "step_up"] do
    with %Scope{user: %{id: user_id}, session: %{strength: :mfa}} <-
           conn.assigns[:current_scope],
         true <- user_id == ticket.user_id,
         {:ok, provider} <- Identity.fetch_oidc_provider(ticket.provider_key) do
      if purpose == "link", do: link(conn, provider, ticket), else: step_up(conn, ticket)
    else
      _ -> reject(conn, ticket, purpose, :session_mismatch)
    end
  end

  defp finish(conn, ticket), do: reject(conn, ticket, ticket.purpose, :ticket_invalid)

  defp sign_in(conn, user, ticket) do
    cond do
      :idp_mfa in ticket.auth_methods ->
        conn
        |> UserAuth.log_in_user(user,
          auth_methods: [:oidc, :idp_mfa],
          strength: :mfa,
          mfa_at: DateTime.utc_now(:second),
          provider_key: ticket.provider_key,
          idp_sid_hash: ticket.idp_sid_hash,
          idp_amr: ticket.idp_amr
        )
        |> SessionController.render_session()

      Accounts.enrolled?(user) ->
        conn
        |> UserAuth.put_pending_second_factor(user, %{
          auth_methods: [:oidc],
          provider_key: ticket.provider_key,
          idp_sid_hash: ticket.idp_sid_hash
        })
        |> json(%{next: "second_factor"})

      true ->
        conn
        |> UserAuth.log_in_user(user,
          auth_methods: [:oidc],
          strength: :enrollment,
          provider_key: ticket.provider_key,
          idp_sid_hash: ticket.idp_sid_hash
        )
        |> json(%{next: "enroll_second_factor"})
    end
  end

  defp link(conn, provider, ticket) do
    case Accounts.link_external_identity(ticket.user_id, provider, ticket.link_identity) do
      {:ok, _linked} ->
        SessionController.render_session(conn, :ok, %{linked: true})

      {:error, reason} when reason in [:identity_in_use, :provider_already_linked] ->
        log_failure(conn, ticket, "link", reason)
        FallbackController.render_error(conn, reason)
    end
  end

  defp step_up(conn, ticket) do
    case UserAuth.step_up(conn, :idp_mfa, %{idp_amr: ticket.idp_amr}) do
      {:ok, conn} ->
        SecurityLog.event(:authn_login_success, %{
          user_id: ticket.user_id,
          provider: ticket.provider_key,
          factor: "idp_mfa",
          purpose: "step_up",
          ip: conn.remote_ip
        })

        SessionController.render_session(conn)

      {:error, :not_found} ->
        reject(conn, ticket, "step_up", :session_mismatch)
    end
  end

  defp reject(conn, ticket, purpose, reason) do
    log_failure(conn, ticket, purpose, reason)
    FallbackController.render_error(conn, :ticket_invalid)
  end

  defp log_failure(conn, ticket, purpose, reason) do
    SecurityLog.event(:authn_login_fail, %{
      provider: ticket && ticket.provider_key,
      purpose: purpose,
      reason: reason,
      ip: conn.remote_ip
    })
  end
end
