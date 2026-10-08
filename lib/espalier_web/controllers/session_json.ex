defmodule EspalierWeb.SessionJSON do
  @moduledoc """
  The session payload of `GET /api/session` and of every sign-in answer
  (README section 6.12). It carries the CSRF token, which rotates at every
  sign-in and sign-out.
  """

  alias Espalier.Accounts.Scope

  @doc "Renders the session payload."
  def show(%{scope: scope, pending: pending}) do
    %{
      user: user(scope),
      roles: roles(scope),
      session: session(scope),
      pending: pending(pending),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      providers: Application.get_env(:espalier, :auth_providers, []),
      flags: %{
        demo: Application.get_env(:espalier, :auth_demo, false),
        local_accounts: Application.get_env(:espalier, :local_accounts, true),
        signup: Atom.to_string(Application.get_env(:espalier, :signup, :closed))
      }
    }
  end

  defp user(%Scope{user: user}) when not is_nil(user) do
    %{id: user.id, display_name: user.display_name, email: user.email, locale: user.locale}
  end

  defp user(_scope), do: nil

  defp roles(%Scope{user: user, roles: roles}) when not is_nil(user),
    do: Enum.map(roles, &Atom.to_string/1)

  defp roles(_scope), do: []

  defp session(%Scope{session: session} = scope) when not is_nil(session) do
    %{
      strength: session.strength,
      auth_methods: session.auth_methods,
      provider_key: session.provider_key,
      recent_auth_until:
        if(Scope.recent_auth?(scope), do: Scope.recent_auth_until(session.mfa_at)),
      expires_at: session.expires_at,
      idle_timeout_minutes: Application.get_env(:espalier, :session_idle_minutes, 60)
    }
  end

  defp session(_scope), do: nil

  defp pending(%{expires_at: expires_at}), do: %{next: "second_factor", expires_at: expires_at}
  defp pending(_pending), do: nil
end
