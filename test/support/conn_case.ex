# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule EspalierWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EspalierWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.

  `api_conn/0` builds a same-origin JSON request, and `with_csrf_token/1`
  adds the CSRF token of the session. A module that calls
  `put_rate_limit/2` sets `async: false`.
  """

  use ExUnit.CaseTemplate

  alias Espalier.Accounts.{Scope, UserToken}
  alias Espalier.{AccountsFixtures, Repo}
  alias EspalierWeb.Plugs.FetchMetadata

  using do
    quote do
      # The default endpoint for testing
      @endpoint EspalierWeb.Endpoint

      use EspalierWeb, :verified_routes
      use Oban.Testing, repo: Espalier.Repo

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Swoosh.TestAssertions
      import Espalier.AccountsFixtures
      import EspalierWeb.ConnCase
      import Espalier.Test.SecurityEvents
    end
  end

  setup tags do
    Espalier.DataCase.setup_sandbox(tags)
    {:ok, conn: api_conn()}
  end

  @doc """
  A conn with `sec-fetch-site: same-origin` and the `origin` of `PUBLIC_URL`.

  `Phoenix.ConnTest.build_conn/0` sets `plug_skip_csrf_protection`, which
  makes `Plug.CSRFProtection` accept any token; the API conns switch it off,
  so every test runs the real check.
  """
  def api_conn do
    put_api_headers(Phoenix.ConnTest.build_conn())
  end

  defp put_api_headers(conn) do
    conn
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("sec-fetch-site", "same-origin")
    |> Plug.Conn.put_req_header("origin", FetchMetadata.public_origin())
  end

  @doc """
  Performs `GET /api/session`, recycles the conn and sets `x-csrf-token`
  from the answer.
  """
  def with_csrf_token(conn) do
    conn = Phoenix.ConnTest.dispatch(conn, EspalierWeb.Endpoint, :get, "/api/session", nil)
    token = Phoenix.ConnTest.json_response(conn, 200)["csrf_token"]

    conn
    |> Phoenix.ConnTest.recycle()
    |> put_api_headers()
    |> Plug.Conn.put_req_header("x-csrf-token", token)
  end

  @doc """
  Recycles a conn after a request for the next request of the same client,
  with the API headers.
  """
  def next_request(conn) do
    conn |> Phoenix.ConnTest.recycle() |> put_api_headers()
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = AccountsFixtures.user_fixture()

    attrs =
      context
      |> Map.take([:session_attrs])
      |> Map.get(:session_attrs, %{})

    conn = log_in_user(conn, user, attrs)
    scope = Scope.for_user(user)
    %{conn: conn, user: user, scope: scope, token: Plug.Conn.get_session(conn, :user_token)}
  end

  @doc """
  Logs the given `user` into the `conn` with a session row of strength
  `mfa`, the methods `[:password, :totp]` and `mfa_at` now, each
  overridable through `attrs`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, attrs \\ %{}) do
    {token, _session} = AccountsFixtures.session_fixture(user, attrs)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  Sends a JSON request of the same client: recycles a sent conn, fetches
  the CSRF token of the session and dispatches. `opts[:ip]` sets the
  remote address of the request.
  """
  def api_request(conn, method, path, body \\ %{}, opts \\ []) do
    conn = if conn.state == :unset, do: conn, else: next_request(conn)
    conn = with_csrf_token(conn)
    conn = if ip = opts[:ip], do: %{conn | remote_ip: ip}, else: conn
    Phoenix.ConnTest.dispatch(conn, EspalierWeb.Endpoint, method, path, body)
  end

  @doc """
  Puts the pending second-factor state of a first factor of `user` into a
  fresh test session, as `UserAuth.put_pending_second_factor/3` writes it.
  `attrs` carries `:auth_methods` (default `[:password]`), `:provider_key`
  and `:idp_sid_hash` (bytes).
  """
  def put_pending(conn, user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    pending = %{
      "user_id" => user.id,
      "auth_methods" => Enum.map(Map.get(attrs, :auth_methods, [:password]), &Atom.to_string/1),
      "provider_key" => attrs[:provider_key],
      "idp_sid_hash" => attrs[:idp_sid_hash] && Base.encode64(attrs[:idp_sid_hash]),
      "expires_at" => System.os_time(:second) + 300
    }

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:pending_second_factor, pending)
  end

  @doc "Returns the raw bytes of `idp_sid_hash` of the session row of `token`."
  def raw_idp_sid_hash(token) do
    %{rows: [[value]]} =
      Repo.query!("SELECT idp_sid_hash FROM users_tokens WHERE token_hash = $1", [
        UserToken.hash(token)
      ])

    value
  end

  @doc "Returns an address `{10, a, b, c}` that no other test uses."
  def unique_ip do
    n = System.unique_integer([:positive])
    {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
  end

  @doc """
  Sets one bucket of `:rate_limits` and restores the previous map when the
  test exits.
  """
  def put_rate_limit(bucket, {scale_ms, limit}) do
    previous = Application.fetch_env!(:espalier, :rate_limits)
    Application.put_env(:espalier, :rate_limits, Map.put(previous, bucket, {scale_ms, limit}))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:espalier, :rate_limits, previous) end)
  end

  @doc "Sets an application setting for one test and restores it on exit."
  def put_setting(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end
end
