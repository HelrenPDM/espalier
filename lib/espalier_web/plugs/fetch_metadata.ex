defmodule EspalierWeb.Plugs.FetchMetadata do
  @moduledoc """
  Rejects cross-site requests with Fetch Metadata (README section 6.5, CSRF
  layer 2; ASVS 3.5.8).

  With a `sec-fetch-site` header, `same-origin`, `same-site` and `none` pass.
  `cross-site` passes only for a GET navigation (`sec-fetch-mode: navigate`)
  to a path of `allow_cross_site_navigation` whose `sec-fetch-dest` is
  neither `object` nor `embed`. Without the header, GET and HEAD pass, and
  every other method needs an `Origin` equal to the origin of `PUBLIC_URL`
  (OWASP CSRF Prevention Cheat Sheet).

  A rejection answers 403 `cross_site_request`, halts and logs
  `malicious_csrf`.

  ## Options

    * `:allow_cross_site_navigation` - a list of `path_info` patterns; the
      atom `:provider` matches one segment.
  """
  @behaviour Plug

  import Plug.Conn

  alias Espalier.SecurityLog

  @impl Plug
  def init(opts), do: Keyword.get(opts, :allow_cross_site_navigation, [])

  @impl Plug
  def call(conn, allowlist) do
    if allowed?(conn, allowlist), do: conn, else: reject(conn)
  end

  defp allowed?(conn, allowlist) do
    case get_req_header(conn, "sec-fetch-site") do
      [site | _] when site in ["same-origin", "same-site", "none"] ->
        true

      ["cross-site" | _] ->
        allowed_navigation?(conn, allowlist)

      [_other | _] ->
        false

      [] ->
        conn.method in ["GET", "HEAD"] or same_origin?(conn)
    end
  end

  defp allowed_navigation?(conn, allowlist) do
    conn.method == "GET" and
      get_req_header(conn, "sec-fetch-mode") == ["navigate"] and
      get_req_header(conn, "sec-fetch-dest") not in [["object"], ["embed"]] and
      Enum.any?(allowlist, &match_path?(&1, conn.path_info))
  end

  defp match_path?([], []), do: true
  defp match_path?([:provider | pattern], [_segment | path]), do: match_path?(pattern, path)
  defp match_path?([segment | pattern], [segment | path]), do: match_path?(pattern, path)
  defp match_path?(_pattern, _path), do: false

  defp same_origin?(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> origin == public_origin()
      _ -> false
    end
  end

  @doc "The origin of `PUBLIC_URL`: scheme, host and port, default ports omitted."
  def public_origin do
    uri = URI.parse(Application.fetch_env!(:espalier, :public_url))

    case {uri.scheme, uri.port} do
      {"http", 80} -> "http://#{uri.host}"
      {"https", 443} -> "https://#{uri.host}"
      {scheme, port} -> "#{scheme}://#{uri.host}:#{port}"
    end
  end

  defp reject(conn) do
    SecurityLog.event(:malicious_csrf, %{ip: conn.remote_ip, reason: :cross_site_request})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, ~s({"error":"cross_site_request"}))
    |> halt()
  end
end
