defmodule EspalierWeb.Me.LdapIdentityController do
  @moduledoc """
  `POST /api/me/identities/ldap/:provider` with `{username, password}`:
  links a directory account to the signed-in account (task 0007, step 20).
  The route needs a second factor from the last 10 minutes.

  The directory password passes the same throttling, counter reservation
  and failure floor as the sign-in. A new link mails "a sign-in method was
  linked" and logs `user_updated`. After the link, the account signs in
  through this directory and its local second factor only.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.LdapSignIn
  alias EspalierWeb.Auth.LdapController
  alias EspalierWeb.Plugs.RateLimit

  action_fallback EspalierWeb.FallbackController

  plug RateLimit, [bucket: :ldap_ip] when action in [:create]

  def create(conn, %{"provider" => key} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, provider} <- LdapController.fetch_provider(key),
         {:ok, username, password} <- LdapController.credentials(params) do
      case LdapSignIn.link(user, provider, username, password, %{ip: conn.remote_ip}) do
        {:ok, status} ->
          json(conn, %{status: Atom.to_string(status)})

        {:error, :rate_limited, retry_after_ms} ->
          RateLimit.too_many_requests(conn, retry_after_ms)

        {:error, _reason} = error ->
          error
      end
    end
  end
end
