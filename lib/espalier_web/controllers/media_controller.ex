defmodule EspalierWeb.MediaController do
  @moduledoc """
  The media route `GET /media/:file` (task 0018, step 13), which serves the
  delivery files and posters of the media store to signed-in users.

  The pipeline `:media` sets the private flag `:espalier_media` first, so
  that `EspalierWeb.Plugs.SecurityHeaders` sends the media CSP with
  `sandbox` on every answer of the route (ASVS 1.3.4, 3.2.1), then runs the
  Fetch Metadata plug without a cross-site allowlist (ASVS 3.5.8) and
  requires a session: 401 `unauthenticated` without one and 403
  `enrollment_required` for an enrollment session.

  The name must be 64 lower-case hex digits, a dot and one of `webp`, `svg`,
  `webm` and `vtt` (ASVS 5.3.2). `Espalier.Media.servable/3` admits the file
  for an author when a `ready` asset names the digest, and for a learner
  only when a published program uses such an asset (ASVS 8.2.2). A
  `Sec-Fetch-Dest` must fit the type: `image` or `document` for images,
  `video`, `audio` or `document` for videos and `track` or `document` for
  captions; a request without the header passes, as the Fetch Metadata plug
  lets it pass. Every other case answers 404 `not_found`, so the route tells
  nobody whether a file exists.

  `Plug.Static` serves the file with the type fixed by the extension
  (ASVS 4.1.1), byte ranges (206, 416), the quoted digest as entity tag
  (304), `content-disposition: inline` with the digest as file name (ASVS
  5.4.1, 5.4.2) and `cache-control: private, max-age=31536000, immutable`,
  also for a `vsn=` query, so that no shared cache stores a media file
  (ASVS 14.2.2).
  """
  use EspalierWeb, :controller

  alias Espalier.Media
  alias Espalier.Media.Store

  action_fallback EspalierWeb.FallbackController

  @types %{
    "webp" => "image/webp",
    "svg" => "image/svg+xml",
    "webm" => "video/webm",
    "vtt" => "text/vtt"
  }

  @destinations %{
    "webp" => ["image", "document"],
    "svg" => ["image", "document"],
    "webm" => ["video", "audio", "document"],
    "vtt" => ["track", "document"]
  }

  @doc "Serves a file of the media store."
  def show(conn, %{"file" => file}) do
    with [_match, sha256, ext] <- Regex.run(~r/\A([0-9a-f]{64})\.(webp|svg|webm|vtt)\z/, file),
         true <- destination?(conn, ext),
         true <- Media.servable(conn.assigns.current_scope, sha256, ext) do
      serve(conn, sha256, ext, file)
    else
      _denied -> {:error, :not_found}
    end
  end

  @doc """
  The entity tag of a media file for `Plug.Static`: the quoted SHA-256 hex
  digest from the file name.
  """
  @spec etag(Path.t()) :: String.t()
  def etag(path), do: ~s("#{Path.basename(path, Path.extname(path))}")

  defp destination?(conn, ext) do
    case get_req_header(conn, "sec-fetch-dest") do
      [] -> true
      [dest | _rest] -> dest in Map.fetch!(@destinations, ext)
    end
  end

  # The options are built per request, because the content type and the
  # file name depend on the file. Every value comes from the store layout and
  # the matched name, never from another part of the request.
  defp serve(conn, sha256, ext, file) do
    <<aa::binary-size(2), bb::binary-size(2), _rest::binary>> = sha256

    opts =
      Plug.Static.init(
        at: "/",
        from: Store.files_root(),
        gzip: false,
        brotli: false,
        etag_generation: {__MODULE__, :etag, []},
        cache_control_for_etags: "private, max-age=31536000, immutable",
        cache_control_for_vsn_requests: nil,
        content_types: %{file => Map.fetch!(@types, ext)},
        headers: %{"content-disposition" => ~s(inline; filename="#{file}")}
      )

    # The path below the store comes from the digest alone (ASVS 5.3.2).
    # sobelow_skip ["Traversal.FileModule"]
    conn = Plug.Static.call(%{conn | path_info: [aa, bb, file]}, opts)

    if conn.state in [:sent, :file, :chunked], do: conn, else: {:error, :not_found}
  end
end
