defmodule EspalierWeb.TransactionCookie do
  @moduledoc """
  The options of both session cookies, and the only access to the sign-in
  transaction cookie `__Host-espalier_tx` outside `Plug.Session`
  (README section 6.5).

  `__Host-espalier` is the Plug session of every `/api` route. It holds the
  session token, the CSRF token, during sign-in the pending second-factor
  state, and the id of a running WebAuthn ceremony; no personal data.
  `__Host-espalier_tx` is the Plug session of the `:oidc_transaction`
  pipeline and holds the data of one OIDC flow for 10 minutes.

  Both cookies are encrypted (`encryption_salt`) and signed with keys
  derived from `SECRET_KEY_BASE`. The salts are no secrets. The helpers
  below write the same format as `Plug.Session` with the same options, so a
  value stored by one is readable by the other.

  A route in the `:oidc_transaction` pipeline uses `get_session/2` and
  `put_session/3` and none of `put/3`, `delete/2` and `clear/1`, because
  `Plug.Session` in that pipeline rewrites the cookie from its own session
  map whenever the route changes the session.
  """

  alias Plug.Session.COOKIE

  @main_session_options [
    store: :cookie,
    key: "__Host-espalier",
    signing_salt: "DnhfSpgVxihiGsIVLLcWyqV8lqKsAnnR",
    encryption_salt: "hQ62+YfpFGDREsAktdEAa/TcNwfLqmFM",
    same_site: "Strict",
    secure: true,
    http_only: true,
    path: "/"
  ]

  @session_options [
    store: :cookie,
    key: "__Host-espalier_tx",
    signing_salt: "ZsFU0A1vVQMoObMB08rcC4Z+4cDV/5zw",
    encryption_salt: "ISv2eVi4euLPTS6V0F52d/4cme0rpV6/",
    same_site: "Lax",
    secure: true,
    http_only: true,
    path: "/",
    max_age: 600
  ]

  @cookie_attributes [:same_site, :secure, :http_only, :path, :max_age]

  @doc "The `Plug.Session` options of the session cookie `__Host-espalier`."
  def main_session_options, do: @main_session_options

  @doc "The `Plug.Session` options of the transaction cookie `__Host-espalier_tx`."
  def session_options, do: @session_options

  @doc """
  Returns the map stored in `__Host-espalier_tx`, or `%{}` when the cookie
  is missing, expired or fails verification. A value written earlier in the
  same request is returned.
  """
  def fetch(conn), do: decode(conn, @session_options)

  @doc "Returns one value of the transaction cookie."
  def get(conn, key), do: Map.get(fetch(conn), to_string(key))

  @doc "Stores one value in the transaction cookie."
  def put(conn, key, value) do
    write(conn, Map.put(fetch(conn), to_string(key), value))
  end

  @doc "Removes one value from the transaction cookie."
  def delete(conn, key) do
    write(conn, Map.delete(fetch(conn), to_string(key)))
  end

  @doc "Deletes the transaction cookie."
  def clear(conn) do
    Plug.Conn.delete_resp_cookie(
      conn,
      @session_options[:key],
      Keyword.take(@session_options, @cookie_attributes)
    )
  end

  @doc """
  Returns the session map of the request's `__Host-espalier` cookie, or
  `%{}` when the cookie is missing or fails verification. It never writes.
  A cross-site navigation carries no `Strict` cookie, so the result is `%{}`
  there.
  """
  def read_main_session(conn) do
    conn = Plug.Conn.fetch_cookies(conn)

    case conn.req_cookies[@main_session_options[:key]] do
      nil -> %{}
      raw -> verify(conn, raw, @main_session_options)
    end
  end

  defp decode(conn, options) do
    conn = Plug.Conn.fetch_cookies(conn)
    key = options[:key]

    case {conn.resp_cookies[key], conn.req_cookies[key]} do
      {%{max_age: 0}, _request} -> %{}
      {%{value: raw}, _request} -> verify(conn, raw, options)
      {nil, nil} -> %{}
      {nil, raw} -> verify(conn, raw, options)
    end
  end

  defp verify(conn, raw, options) do
    case COOKIE.get(conn, raw, store_options(options)) do
      {_sid, %{} = session} -> session
      _ -> %{}
    end
  end

  defp write(conn, session) do
    raw = COOKIE.put(conn, nil, session, store_options(@session_options))

    Plug.Conn.put_resp_cookie(
      conn,
      @session_options[:key],
      raw,
      Keyword.take(@session_options, @cookie_attributes)
    )
  end

  defp store_options(options) do
    options
    |> Keyword.drop([:store, :key | @cookie_attributes])
    |> COOKIE.init()
  end
end
