defmodule EspalierWeb.Plugs.ApiClientAuth do
  @moduledoc """
  Authenticates a machine client of the integration API (README section
  11) by the bearer token in the `authorization` header, through
  `Espalier.Accounts.get_api_client_by_token/1`.

  A missing or unknown token answers 401 `unauthenticated` and logs
  `authn_login_fail` with the factor `api_token`. A client whose `scopes`
  lack the scope of the plug answers 403 `forbidden` and logs `authz_fail`
  (ASVS 16.3.2). Otherwise the plug assigns `api_client`. The token never
  reaches the log (ASVS 16.2.5).

      plug EspalierWeb.Plugs.ApiClientAuth, scope: "credentials:read"
  """
  @behaviour Plug

  import Plug.Conn

  alias Espalier.Accounts
  alias Espalier.Accounts.ApiClient
  alias Espalier.SecurityLog

  @impl Plug
  def init(opts) do
    scope = Keyword.fetch!(opts, :scope)

    if scope not in ApiClient.allowed_scopes() do
      raise ArgumentError, "unknown API client scope #{inspect(scope)}"
    end

    scope
  end

  @impl Plug
  def call(conn, scope) do
    with {:ok, token} <- bearer_token(conn),
         %ApiClient{} = client <- Accounts.get_api_client_by_token(token) do
      if scope in client.scopes do
        assign(conn, :api_client, client)
      else
        SecurityLog.event(:authz_fail, %{ip: conn.remote_ip, factor: :api_token, reason: :scope})
        halt_with(conn, 403, "forbidden")
      end
    else
      _missing_or_unknown ->
        SecurityLog.event(:authn_login_fail, %{ip: conn.remote_ip, factor: :api_token})

        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> halt_with(401, "unauthenticated")
    end
  end

  # One authorization header with the scheme Bearer (case-insensitive) and
  # a token of the base64url alphabet.
  defp bearer_token(conn) do
    with [value] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(value, " ", parts: 2, trim: true),
         "bearer" <- String.downcase(scheme),
         token = String.trim(token),
         true <- token != "" and byte_size(token) <= 256 do
      {:ok, token}
    else
      _other -> :error
    end
  end

  defp halt_with(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(%{error: code}))
    |> halt()
  end
end
