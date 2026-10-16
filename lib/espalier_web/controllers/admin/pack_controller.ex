defmodule EspalierWeb.Admin.PackController do
  @moduledoc """
  Upload, preview data, diff and publication of content packs for the role
  `author` (task 0015, step 7; README section 11).

  The upload is a `multipart/form-data` body with the zip archive in the
  field `file`. Only the router pipeline `:pack_upload` reads it, behind
  `:author_write` and up to `PACK_UPLOAD_MAX_MB` (413 above it, 415 for
  another content type). `Espalier.Catalog.Pack.Archive` checks the central
  directory before any extraction and extracts into a new directory below
  `System.tmp_dir!/0`, which an `after` block removes; a rejected archive
  answers 422 with the report. The importer of task 0008 then validates the
  pack with the author as actor.

  A publish runs for a `validated` import only (409 `not_publishable`
  otherwise) and is refused with 409 `alignment_errors` while
  `Espalier.Catalog.Alignment.check/1` reports an error on the stored
  payload, and with 409 `media_not_ready` and the entries while a media
  file of the payload is not `ready` (task 0018, step 10).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.Archive
  alias EspalierWeb.Admin.PackJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.PackMultipart
  alias EspalierWeb.Schemas.{Admin, EmptyRequest, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: packs"]

  @id [id: [in: :path, required: true, description: "The import id.", schema: Fields.uuid()]]

  operation :create,
    summary: "Upload a content pack",
    description:
      "A zip archive of at most `PACK_UPLOAD_MAX_MB` (default 20) with at most 2,000 " <>
        "entries and declared sizes of at most five times that limit. The folder `media/` " <>
        "holds at most 500 files (`max_pack_media`), whether a lesson references them " <>
        "or not, and each of them must pass the media path rules and the size limit of " <>
        "its kind: images `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, SVG `.svg`, " <>
        "videos `.mp4`, `.m4v`, `.mov`, `.webm`, `.mkv` and captions `.vtt`. Only the " <>
        "files that a lesson references become assets of the media library. The archive " <>
        "stays within `PACK_UPLOAD_MAX_MB`, so larger videos come through the media " <>
        "library or an external URL.",
    security: Responses.session_and_csrf(),
    request_body:
      {"The archive", "multipart/form-data",
       %Schema{
         title: "AdminPackUpload",
         type: :object,
         properties: %{file: %Schema{type: :string, format: :binary}},
         required: [:file],
         additionalProperties: false
       }, required: true},
    responses:
      Map.merge(
        %{
          201 => {"The import", "application/json", Admin.PackImport},
          422 => {"The rejected archive", "application/json", Admin.ArchiveRejected}
        },
        Responses.errors(
          Responses.author_write([
            {413, ["request_too_large"]},
            {415, ["unsupported_media_type"]}
          ])
        )
      )

  # The schema admits a string for a binary field, so a text part named
  # `file` reaches the action and answers 422 here.
  def create(conn, _params) do
    case conn.body_params do
      %{file: %Plug.Upload{path: path}} ->
        import_upload(conn, path)

      _text ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", fields: %{file: ["invalid_type"]}})
    end
  end

  defp import_upload(conn, path) do
    scope = conn.assigns.current_scope

    result =
      Archive.with_extracted(path, PackMultipart.max_bytes(), fn dir ->
        Catalog.import_pack(scope, Archive.pack_root(dir))
      end)

    case result do
      {:ok, pack_import} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/admin/packs/#{pack_import.id}")
        |> json(PackJSON.show(%{pack_import: pack_import}))

      {:error, entries} when is_list(entries) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(PackJSON.archive_rejected(%{entries: entries}))

      {:error, _reason} = error ->
        error
    end
  end

  operation :show,
    summary: "Read an import",
    description: "A `validated` import carries its payload with the answer keys.",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The import", "application/json", Admin.PackImport}},
        Responses.errors(
          Responses.author_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, pack_import} <- Catalog.get_pack_import(conn.assigns.current_scope, id) do
      json(conn, PackJSON.show(%{pack_import: pack_import}))
    end
  end

  operation :diff,
    summary: "Compare an import with the live program",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The diff", "application/json", Admin.PackDiff}},
        Responses.errors(
          Responses.author_read([
            {404, ["not_found"]},
            {409, ["not_publishable"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def diff(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, pack_import} <- Catalog.get_pack_import(scope, id),
         {:ok, diff} <- Catalog.pack_diff(scope, pack_import) do
      json(conn, PackJSON.diff(%{diff: diff}))
    end
  end

  operation :publish,
    summary: "Publish an import",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{
          200 => {"The published import", "application/json", Admin.PackImport},
          409 =>
            {"Error codes: `not_publishable`, `alignment_errors`, `media_not_ready`",
             "application/json", %Schema{oneOf: [Admin.AlignmentErrors, Admin.MediaNotReady]}}
        },
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def publish(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, pack_import} <- Catalog.get_pack_import(scope, id) do
      case Catalog.publish_pack(scope, pack_import) do
        {:ok, published} ->
          json(conn, PackJSON.show(%{pack_import: published}))

        {:error, {:alignment_errors, findings}} ->
          conn
          |> put_status(:conflict)
          |> json(PackJSON.alignment_errors(%{findings: findings}))

        {:error, _reason} = error ->
          error
      end
    end
  end
end
