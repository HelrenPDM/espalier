defmodule EspalierWeb.Admin.MediaController do
  @moduledoc """
  The media library for the role `author` (task 0018, step 15; README
  section 8, row "Administration").

  The reads run in `:author`, and every change in `:author_write`, so it
  needs a second factor from the last 10 minutes (README section 6.4). The
  upload is a `multipart/form-data` body with one part `file`, which only
  the router pipeline `:media_upload` reads, up to the larger of
  `MEDIA_IMAGE_MAX_MB` and `MEDIA_VIDEO_MAX_MB` (413 above it, 415 for
  another content type). `Espalier.Media.ingest/3` then detects the type
  from the leading bytes, applies the limit of the detected kind and queues
  the conversion: 201 with a new asset, 200 with an existing asset of the
  same file, 422 `validation_failed` with `fields.file`, and 409
  `storage_full`, also when the volume fills up while the body arrives.

  A deletion answers 409 `asset_in_use` with the uses while a published
  program or a draft uses the asset, which this controller renders itself.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Media
  alias EspalierWeb.Admin.MediaJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: media"]

  @id [id: [in: :path, required: true, description: "The asset id.", schema: Fields.uuid()]]

  @types "Accepted files, detected from their leading bytes, with the extension of the " <>
           "detected kind: images `.png` (`89 50 4E 47 0D 0A 1A 0A`), `.jpg` and `.jpeg` " <>
           "(`FF D8 FF`), `.gif` (`GIF87a`, `GIF89a`) and `.webp` (`RIFF`, four bytes, " <>
           "`WEBP`) of at most `MEDIA_IMAGE_MAX_MB` (default 20) and 40,000,000 pixels; " <>
           "SVG `.svg` (`<?xml`, `<svg` or `<!--` after an optional BOM) of at most " <>
           "1,048,576 bytes; videos `.mp4`, `.m4v` and `.mov` (`ftyp` at offset 4, no HEIF " <>
           "brand) and `.webm` and `.mkv` (`1A 45 DF A3`) of at most `MEDIA_VIDEO_MAX_MB` " <>
           "(default 1024), `MEDIA_VIDEO_MAX_MINUTES` (default 60) and 3840 by 2160 pixels; " <>
           "captions `.vtt` (`WEBVTT`) of at most 524,288 bytes. Images become WebP with " <>
           "at most `MEDIA_IMAGE_MAX_EDGE` pixels per edge (animated images at most 1,000 " <>
           "frames), videos WebM with VP9 and Opus at most `MEDIA_VIDEO_MAX_HEIGHT` high, " <>
           "SVG files are rebuilt from an allowlist, and captions are checked. The media " <>
           "store holds at most `MEDIA_STORAGE_MAX_GB` (default 50)."

  operation :index,
    summary: "List the media library",
    description: "Newest first, with an opaque cursor in `next`.",
    security: Responses.session(),
    parameters: [
      kind: [in: :query, schema: Fields.enum(~w(image svg video captions)), required: false],
      status: [
        in: :query,
        schema: Fields.enum(~w(queued processing ready failed)),
        required: false
      ],
      unused: [
        in: :query,
        schema: %Schema{type: :boolean},
        required: false,
        description: "Only assets that no program, draft or validated import uses."
      ],
      q: [
        in: :query,
        schema: %Schema{type: :string, maxLength: 255},
        required: false,
        description: "A case-insensitive part of the title."
      ],
      limit: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100},
        required: false,
        description: "At most 100, default 50."
      ],
      after: [
        in: :query,
        schema: %Schema{type: :string, maxLength: 200},
        required: false,
        description: "The `next` cursor of the previous page."
      ]
    ],
    responses:
      Map.merge(
        %{200 => {"The page", "application/json", Admin.MediaAssetList}},
        Responses.errors(Responses.author_read([{422, ["validation_failed"]}]))
      )

  def index(conn, params) do
    filters = Map.take(params, [:kind, :status, :unused, :q, :limit, :after])

    with {:ok, page} <- Media.list_assets(conn.assigns.current_scope, filters) do
      json(conn, MediaJSON.index(page))
    end
  end

  operation :show,
    summary: "Read an asset with its uses",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The asset", "application/json", Admin.MediaAsset}},
        Responses.errors(
          Responses.author_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, asset, uses} <- Media.get_asset(conn.assigns.current_scope, id) do
      json(conn, MediaJSON.show(%{asset: asset, uses: uses}))
    end
  end

  operation :create,
    summary: "Upload a media file",
    description: @types,
    security: Responses.session_and_csrf(),
    request_body:
      {"The file", "multipart/form-data",
       %Schema{
         title: "AdminMediaUpload",
         type: :object,
         properties: %{file: %Schema{type: :string, format: :binary}},
         required: [:file],
         additionalProperties: false
       }, required: true},
    responses:
      Map.merge(
        %{
          201 => {"The new asset", "application/json", Admin.MediaAsset},
          200 => {"The existing asset of the same file", "application/json", Admin.MediaAsset}
        },
        Responses.errors(
          Responses.author_write([
            {409, ["storage_full"]},
            {413, ["request_too_large"]},
            {415, ["unsupported_media_type"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  # The schema admits a string for a binary field, so a text part named
  # `file` reaches the action and answers 422 here. The parser puts the
  # text "storage_full" into `file` when the volume filled up while the body
  # arrived, which a text part never gives.
  def create(conn, _params) do
    case conn.body_params do
      %{file: %Plug.Upload{path: path, filename: file_name}} ->
        upload(conn, path, file_name)

      %{file: "storage_full"} ->
        {:error, :storage_full}

      _text ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", fields: %{file: ["invalid_type"]}})
    end
  end

  # Bandit keeps the request process of a keep-alive connection, which owns
  # the temporary file of Plug.Upload, until the connection closes; the
  # file is removed here when the ingest did not move it into the store.
  # The path is the temporary file that Plug.Upload created for this request.
  # sobelow_skip ["Traversal.FileModule"]
  defp upload(conn, path, file_name) do
    case Media.ingest(conn.assigns.current_scope, %{path: path, file_name: file_name}) do
      {:ok, asset, created_or_existing} ->
        conn
        |> put_status(if created_or_existing == :created, do: :created, else: :ok)
        |> put_resp_header("location", ~p"/api/admin/media/#{asset.id}")
        |> json(MediaJSON.asset(asset))

      {:error, _reason} = error ->
        error
    end
  after
    _ignored = File.rm(path)
  end

  operation :update,
    summary: "Change the title of an asset",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"The title", "application/json", Admin.MediaUpdate, required: true},
    responses:
      Map.merge(
        %{200 => {"The asset", "application/json", Admin.MediaAsset}},
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def update(conn, %{id: id}) do
    with {:ok, asset} <-
           Media.update_asset(conn.assigns.current_scope, id, %{title: conn.body_params.title}) do
      json(conn, MediaJSON.asset(asset))
    end
  end

  operation :delete,
    summary: "Delete an asset",
    description: "Refused with 409 `asset_in_use` while a published program or a draft uses it.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{
          204 => "The asset is deleted",
          409 => {"Error code: `asset_in_use`", "application/json", Admin.MediaInUse}
        },
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def delete(conn, %{id: id}) do
    case Media.delete_asset(conn.assigns.current_scope, id) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, {:asset_in_use, uses}} ->
        conn
        |> put_status(:conflict)
        |> json(MediaJSON.asset_in_use(%{uses: uses}))

      {:error, _reason} = error ->
        error
    end
  end
end
