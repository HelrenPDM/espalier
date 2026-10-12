defmodule EspalierWeb.PackMultipart do
  @moduledoc """
  The multipart parser of the content pack upload (task 0015, step 7). It
  wraps `Plug.Parsers.MULTIPART` with `length` taken from
  `PACK_UPLOAD_MAX_MB` (`config :espalier, :pack_upload_max_mb`, default 20),
  as the section "Dynamic configuration" of `Plug.Parsers.MULTIPART` shows,
  so that the server reads an upload only up to that limit and answers 413
  above it (`Plug.Parsers.RequestTooLargeError`, ASVS 5.2.1).

  The endpoint parses no multipart body, so only the router pipeline
  `:pack_upload` reads one, behind the checks of `:author_write`.
  `require_multipart/2` runs before the parser in that pipeline and answers
  415 for any other content type, also for a JSON body that the endpoint
  has parsed already.
  """
  @behaviour Plug.Parsers

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Plug.Conn.Utils

  @multipart Plug.Parsers.MULTIPART

  @doc "The upload limit in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: Application.get_env(:espalier, :pack_upload_max_mb, 20) * 1024 * 1024

  @impl Plug.Parsers
  def init(opts), do: opts

  @impl Plug.Parsers
  def parse(conn, "multipart", subtype, headers, opts) do
    opts = @multipart.init([length: max_bytes()] ++ opts)
    @multipart.parse(conn, "multipart", subtype, headers, opts)
  end

  def parse(conn, _type, _subtype, _headers, _opts), do: {:next, conn}

  @doc """
  A function plug: passes a `multipart/form-data` request and answers 415
  `{"error":"unsupported_media_type"}` otherwise.
  """
  def require_multipart(conn, _opts) do
    with [header | _rest] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", _params} <- Utils.content_type(header) do
      conn
    else
      _other ->
        conn
        |> put_status(:unsupported_media_type)
        |> json(%{error: "unsupported_media_type"})
        |> halt()
    end
  end
end
