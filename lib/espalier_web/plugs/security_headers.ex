defmodule EspalierWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Sets the security headers of README section 6.5 on every response: the
  SPA, the static assets, `/health` and the API. The endpoint runs it before
  `Plug.Static`. `/api/session`, `/api/auth/*` and `/api/me/*` also receive
  `cache-control: no-store`. HSTS comes from the reverse proxy (task 0017).
  """
  @behaviour Plug

  @headers [
    {"content-security-policy",
     "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " <>
       "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"},
    {"content-security-policy-report-only", "require-trusted-types-for 'script'"},
    {"cross-origin-opener-policy", "same-origin"},
    {"cross-origin-resource-policy", "same-origin"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"x-content-type-options", "nosniff"},
    {"permissions-policy",
     "camera=(), microphone=(), geolocation=(), payment=(), usb=(), " <>
       "publickey-credentials-create=(self), publickey-credentials-get=(self)"}
  ]

  @vary ["Sec-Fetch-Site", "Sec-Fetch-Mode", "Sec-Fetch-Dest"]

  @doc "The fixed headers of every response."
  def headers, do: @headers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, &put_headers/1)
  end

  defp put_headers(conn) do
    conn
    |> Plug.Conn.merge_resp_headers(@headers)
    |> put_vary()
    |> put_no_store()
  end

  defp put_vary(conn) do
    existing =
      conn
      |> Plug.Conn.get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    values =
      Enum.uniq_by(existing ++ @vary, &String.downcase/1)

    Plug.Conn.put_resp_header(conn, "vary", Enum.join(values, ", "))
  end

  defp put_no_store(%Plug.Conn{path_info: ["api", "session"]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "auth" | _]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "me" | _]} = conn), do: no_store(conn)
  defp put_no_store(conn), do: conn

  defp no_store(conn), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
end
