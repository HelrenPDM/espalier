defmodule EspalierWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Sets the security headers of README section 6.5 on every response: the
  SPA, the static assets, `/health` and the API. The endpoint runs it before
  `Plug.Static`. `/api/session`, `/api/auth/*` and `/api/me/*` also receive
  `cache-control: no-store`, and since task 0013 so do `/api/facilitator/*`,
  `/api/registrar/*`, `/api/integration/*`, the attendance route
  `/api/formats/:id/attendance` and `GET /api/policies`, which carries the
  user's own acknowledgements, because they return personal data (ASVS
  14.2.2 and 14.3.2). Task 0014 adds the analyst reports `/api/insights/*`.
  Task 0015 adds the admin area `/api/admin/*`, whose answers carry API
  tokens once and pack payloads with answer keys. HSTS comes from the
  reverse proxy (task 0017).

  `Plug.Static` sends the type of `MIME.from_path/1` without a charset, so
  the callback appends `; charset=utf-8` to a `text/*`, `*/*+xml` or
  `*/xml` type without one, such as `text/javascript` and `text/css` of the
  SPA assets and `image/svg+xml` of its icon (ASVS 4.1.1, task 0017), and
  `image/svg+xml` and `text/vtt` of the media route (task 0018).

  ## Media (task 0018, steps 13 and 14)

  The CSP of the application comes from `csp/2`, a pure function of the
  hosts of `MEDIA_EXTERNAL_HOSTS` and `MEDIA_EMBED_HOSTS`: the base of
  README section 6.5, followed by `; media-src 'self' https://<host>` for
  external video files and `; frame-src https://<host>` for the players of
  streaming services when a list is not empty, hosts in the order of the
  variable. With both lists empty it is the base byte for byte.
  `Espalier.Application` stores the result for the configured lists with
  `put_csp/2` at start, and the callback reads it there; the plug computes
  nothing in `init/1`, because the endpoint initializes its plugs at
  compile time in production.

  A conn whose private `:espalier_media` is true, which the router pipeline
  `:media` sets before anything else, gets the CSP `default-src 'none';
  style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none';
  sandbox` in place of the CSP of the application and no `no-store`; every
  other header stays. The flag is set before `EspalierWeb.MediaController`
  rewrites `path_info`, so the rule holds for every answer of the media
  route, the 401 and 404 answers included.
  """
  @behaviour Plug

  @base_csp "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; " <>
              "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"

  @media_csp "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; " <>
               "frame-ancestors 'none'; sandbox"

  @csp_key {__MODULE__, :csp}

  @headers [
    {"content-security-policy", @base_csp},
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

  @doc "The fixed headers of every response, with the base CSP of README section 6.5."
  def headers, do: @headers

  @doc "The CSP of the media route (task 0018, step 13)."
  @spec media_csp() :: String.t()
  def media_csp, do: @media_csp

  @doc """
  The CSP of the application for the external file hosts and the embed
  hosts, each `{host, port | nil}`: the base CSP with `media-src` and
  `frame-src` appended for a list that is not empty.
  """
  @spec csp([{String.t(), pos_integer() | nil}], [{String.t(), pos_integer() | nil}]) ::
          String.t()
  def csp(external_hosts, embed_hosts) do
    @base_csp <>
      directive("media-src", ["'self'" | sources(external_hosts)], external_hosts) <>
      directive("frame-src", sources(embed_hosts), embed_hosts)
  end

  defp directive(_name, _sources, []), do: ""
  defp directive(name, sources, _hosts), do: "; " <> name <> " " <> Enum.join(sources, " ")

  defp sources(hosts) do
    Enum.map(hosts, fn
      {host, nil} -> "https://" <> host
      {host, port} -> "https://#{host}:#{port}"
    end)
  end

  @doc """
  Stores the CSP of the application for the configured hosts;
  `Espalier.Application` calls it at start.
  """
  @spec put_csp([{String.t(), pos_integer() | nil}], [{String.t(), pos_integer() | nil}]) :: :ok
  def put_csp(external_hosts, embed_hosts) do
    :persistent_term.put(@csp_key, csp(external_hosts, embed_hosts))
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, &put_headers/1)
  end

  defp put_headers(%Plug.Conn{private: %{espalier_media: true}} = conn) do
    conn
    |> Plug.Conn.merge_resp_headers(@headers)
    |> Plug.Conn.put_resp_header("content-security-policy", @media_csp)
    |> put_vary()
    |> put_charset()
  end

  defp put_headers(conn) do
    conn
    |> Plug.Conn.merge_resp_headers(@headers)
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      :persistent_term.get(@csp_key, @base_csp)
    )
    |> put_vary()
    |> put_no_store()
    |> put_charset()
  end

  defp put_charset(conn) do
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [type] ->
        if needs_charset?(String.downcase(type)),
          do: Plug.Conn.put_resp_header(conn, "content-type", type <> "; charset=utf-8"),
          else: conn

      _other ->
        conn
    end
  end

  # The media types that ASVS 4.1.1 names: text/*, */*+xml and */xml.
  defp needs_charset?(type) do
    media_type = type |> String.split(";", parts: 2) |> hd() |> String.trim()

    (String.starts_with?(media_type, "text/") or String.ends_with?(media_type, ["+xml", "/xml"])) and
      not String.contains?(type, "charset=")
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
  defp put_no_store(%Plug.Conn{path_info: ["api", "facilitator" | _]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "registrar" | _]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "integration" | _]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "policies"]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "insights" | _]} = conn), do: no_store(conn)
  defp put_no_store(%Plug.Conn{path_info: ["api", "admin" | _]} = conn), do: no_store(conn)

  defp put_no_store(%Plug.Conn{path_info: ["api", "formats", _id, "attendance"]} = conn),
    do: no_store(conn)

  defp put_no_store(conn), do: conn

  defp no_store(conn), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
end
