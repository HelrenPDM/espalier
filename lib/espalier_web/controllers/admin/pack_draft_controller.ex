defmodule EspalierWeb.Admin.PackDraftController do
  @moduledoc """
  The drafts of the pack workbench for the role `author` (task 0016a, step
  9; README section 8, row "Pack workbench").

  The GET routes and the check run in `:author`: the check writes the files
  into a temporary directory, which it removes, and changes no state. Every
  other POST and the DELETE route run in `:author_write`, so a change needs
  a second factor from the last 10 minutes (README section 6.4). The upload
  of an archive runs in `:author_write` and `:pack_upload`, which reads the
  body only behind the checks of `:author_write` and up to
  `PACK_UPLOAD_MAX_MB` (ASVS 5.2.1).

  `Espalier.Workbench.CheckLimiter` admits at most
  `Espalier.Workbench.max_parallel_checks/0` checks, imports and zip builds
  of downloads at once, and `Espalier.Workbench.DownloadLimiter` at most
  `Espalier.Workbench.max_parallel_downloads/0` downloads, one per user;
  another one answers 429 `checks_busy` with `retry-after: 5`. A request
  with a `lock_version` that differs from the stored one answers 409
  `stale_draft` with the stored version, which this controller renders
  itself. The download sends the zip with the generated name
  `<pack key>-draft.zip` through `EspalierWeb.BlockDownload.send_download/3`,
  which sets the headers of `Phoenix.Controller.send_download/3`, so no
  request parameter names a file (ASVS 5.4.1 and 5.4.2). It sends the zip
  after its build has freed the slot of the checks, in blocks of 64 KiB,
  and keeps its slot of the downloads until the transfer has ended and the
  staging directory is removed. The transfer ends at its deadline, the time
  of the zip at `Espalier.Workbench.download_min_bytes_per_second/0` and at
  least `Espalier.Workbench.download_floor_seconds/0`, and a client that
  reads nothing for the send timeout of the socket, 30 seconds, loses the
  connection before it.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Workbench
  alias EspalierWeb.Admin.{PackDraftJSON, PackJSON}
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.{BlockDownload, PackMultipart}
  alias EspalierWeb.Schemas.{Admin, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: pack workbench"]

  @id [id: [in: :path, required: true, description: "The draft id.", schema: Fields.uuid()]]

  @limits "A draft holds at most 2,000 files of at most 1,048,576 bytes each and at most " <>
            "five times `PACK_UPLOAD_MAX_MB` (default 20) in total; at most 50 drafts exist."

  # The members of POST /api/admin/pack-drafts per source.
  @source_members %{
    "empty" => :name,
    "program" => :program_slug,
    "import" => :pack_import_id
  }

  operation :index,
    summary: "List the drafts",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The drafts, newest change first", "application/json", Admin.PackDraftList}},
        Responses.errors(Responses.author_read())
      )

  def index(conn, _params) do
    with {:ok, drafts} <- Workbench.list_drafts(conn.assigns.current_scope) do
      json(conn, PackDraftJSON.index(%{drafts: drafts}))
    end
  end

  operation :show,
    summary: "Read a draft with its files",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The draft", "application/json", Admin.PackDraft}},
        Responses.errors(
          Responses.author_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, draft} <- Workbench.get_draft(conn.assigns.current_scope, id) do
      json(conn, PackDraftJSON.show(%{draft: draft}))
    end
  end

  operation :create,
    summary: "Start a draft",
    description:
      "Starts a draft from an empty pack (`name`), a published program (`program_slug`) " <>
        "or an import with a payload (`pack_import_id`). " <> @limits,
    security: Responses.session_and_csrf(),
    request_body:
      {"The starting point", "application/json", Admin.PackDraftRequest, required: true},
    responses:
      Map.merge(
        %{
          201 => {"The draft", "application/json", Admin.PackDraft},
          409 =>
            {"Error codes: `draft_limit`, `no_payload`, `too_many_files`, `draft_too_large`, " <>
               "`media_limit`, and `media_not_ready` with the captions files that are not " <>
               "ready yet", "application/json",
             %Schema{oneOf: [Admin.StaleDraft, Admin.MediaNotReady]}}
        },
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def create(conn, _params) do
    scope = conn.assigns.current_scope
    body = conn.body_params

    with :ok <- source_members(body) do
      result =
        case body do
          %{source: "empty", name: name} -> Workbench.create_empty(scope, name)
          %{source: "program", program_slug: slug} -> Workbench.create_from_program(scope, slug)
          %{source: "import", pack_import_id: id} -> Workbench.create_from_import(scope, id)
        end

      with {:ok, draft} <- result do
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/admin/pack-drafts/#{draft.id}")
        |> json(PackDraftJSON.show(%{draft: draft}))
      end
    end
  end

  # The member of the source is required, and a member of another source
  # is not allowed.
  defp source_members(%{source: source} = body) do
    fields =
      for {other, member} <- @source_members,
          code = member_code(other == source, Map.has_key?(body, member)),
          into: %{},
          do: {member, [code]}

    if fields == %{}, do: :ok, else: {:error, {:fields, fields}}
  end

  defp member_code(true, false), do: "required"
  defp member_code(false, true), do: "not_allowed"
  defp member_code(_own?, _present?), do: nil

  operation :upload,
    summary: "Start a draft from a zip archive",
    description:
      "A zip archive of at most `PACK_UPLOAD_MAX_MB` (default 20) with at most 2,000 " <>
        "entries and declared sizes of at most five times that limit, with the pack at " <>
        "its root or in its one top-level directory. The draft keeps the files of the " <>
        "pack layout (`pack.yaml`, `sources.yaml`, `glossary.yaml`, `segments.yaml`, " <>
        "`stations.yaml`, `feedback.yaml`, `qualifications.yaml`, `formats.yaml`, " <>
        "`modules/<dir>/{module,objectives,rules,items,assessment}.yaml` and " <>
        "`modules/<dir>/lessons/<key>.md`) and the captions files `.vtt` below `media/` " <>
        "as text files; each kept file is UTF-8 text without U+0000 of at most " <>
        "1,048,576 bytes. Every other file below `media/` whose path passes the media " <>
        "path rules, at most 500 (`max_draft_media`), becomes an asset of the media " <>
        "library and a media entry of the draft at its delivery path (`.webp`, `.svg` or " <>
        "`.webm`), and the directives of the lessons follow the new paths. A media file " <>
        "that the library refuses and two media files with one delivery path reject the " <>
        "archive with 422 entries at their paths. These media files never appear in " <>
        "`skipped`, which lists every other file of the archive. " <> @limits,
    security: Responses.session_and_csrf(),
    request_body:
      {"The archive", "multipart/form-data",
       %Schema{
         title: "AdminPackDraftUpload",
         type: :object,
         properties: %{file: %Schema{type: :string, format: :binary}},
         required: [:file],
         additionalProperties: false
       }, required: true},
    responses:
      Map.merge(
        %{
          201 => {"The draft with the skipped paths", "application/json", Admin.PackDraft},
          409 =>
            {"Error codes: `draft_limit`, `too_many_files`, `draft_too_large`, and " <>
               "`media_limit` for more than 500 media files below `media/` other than " <>
               "captions (`max_draft_media`)", "application/json", Admin.StaleDraft},
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
  def upload(conn, _params) do
    case conn.body_params do
      %{file: %Plug.Upload{path: path, filename: filename}} ->
        create_from_upload(conn, path, filename)

      _text ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", fields: %{file: ["invalid_type"]}})
    end
  end

  defp create_from_upload(conn, path, filename) do
    scope = conn.assigns.current_scope

    case Workbench.create_from_upload(scope, path, filename, PackMultipart.max_bytes()) do
      {:ok, draft, skipped} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/admin/pack-drafts/#{draft.id}")
        |> json(PackDraftJSON.upload(%{draft: draft, skipped: skipped}))

      {:error, entries} when is_list(entries) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(PackJSON.archive_rejected(%{entries: entries}))

      {:error, _reason} = error ->
        error
    end
  end

  operation :delete,
    summary: "Delete a draft with its files",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{204 => "The draft is deleted"},
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def delete(conn, %{id: id}) do
    with {:ok, _draft} <- Workbench.delete_draft(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation :check,
    summary: "Check a draft without saving it",
    description:
      "Runs the loader and the validator of the pack format on the files of the draft, " <>
        "with the unsaved `content` of the file `file_id` when both are given, and " <>
        "changes no state. At most two checks, imports and zip builds of draft downloads " <>
        "run at once.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The overlay", "application/json", Admin.PackDraftCheckRequest, required: false},
    responses:
      Map.merge(
        %{
          200 => {"The check", "application/json", Admin.PackDraftCheck},
          409 => {"Error code: `draft_too_large`", "application/json", Admin.StaleDraft}
        },
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["forbidden", "enrollment_required", "csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]},
          {429, ["checks_busy"]}
        ])
      )

  def check(conn, %{id: id}) do
    with {:ok, overlay} <- overlay(conn.body_params),
         {:ok, check} <- Workbench.check_draft(conn.assigns.current_scope, id, overlay) do
      json(conn, PackDraftJSON.check(%{check: check}))
    end
  end

  defp overlay(%{file_id: file_id, content: content}),
    do: {:ok, %{file_id: file_id, content: content}}

  defp overlay(%{file_id: _file_id}), do: {:error, {:fields, %{content: ["required"]}}}
  defp overlay(%{content: _content}), do: {:error, {:fields, %{file_id: ["required"]}}}
  defp overlay(_body), do: {:ok, nil}

  operation :create_import,
    summary: "Import a draft",
    description:
      "Validates the files of the draft as an upload of the same files would and stores " <>
        "the import; the pack page continues with report, diff, preview and publish. " <>
        "The draft stays. At most two checks, imports and zip builds of draft downloads " <>
        "run at once.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The version of the draft", "application/json", Admin.PackDraftImportRequest,
       required: true},
    responses:
      Map.merge(
        %{
          201 => {"The import", "application/json", Admin.PackImport},
          409 => {"Error code: `stale_draft`", "application/json", Admin.StaleDraft}
        },
        Responses.errors(
          Responses.author_write([
            {404, ["not_found"]},
            {422, ["validation_failed"]},
            {429, ["checks_busy"]}
          ])
        )
      )

  def create_import(conn, %{id: id}) do
    %{lock_version: lock_version} = conn.body_params

    case Workbench.import_draft(conn.assigns.current_scope, id, lock_version) do
      {:ok, pack_import} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/admin/packs/#{pack_import.id}")
        |> json(PackJSON.show(%{pack_import: pack_import}))

      {:error, {:stale_draft, current}} ->
        conn
        |> put_status(:conflict)
        |> json(PackDraftJSON.stale_draft(%{lock_version: current}))

      {:error, _reason} = error ->
        error
    end
  end

  operation :download,
    summary: "Download a draft as a zip archive",
    description:
      "Sends the files and the media files in the pack layout at the root of a zip " <>
        "archive named `<pack key>-draft.zip`, or `pack-draft.zip` without a usable " <>
        "pack key. The media of a draft stay within `export_max_mb` (1,024 MB; 409 " <>
        "`download_too_large`), and a media file that is not ready answers 409 " <>
        "`media_not_ready`. At most two downloads run at once, one per user; a " <>
        "download builds the archive in one of the two slots of the checks and " <>
        "imports and frees it before the transfer. When the user runs a download " <>
        "already or no slot is free, the download answers 429 `checks_busy` and " <>
        "builds nothing. The transfer ends at its deadline, the size of the archive " <>
        "at 256 KiB per second and at least 60 seconds, or when the client reads " <>
        "nothing for 30 seconds; the client then holds fewer bytes than " <>
        "`content-length`.",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The archive", "application/zip", %Schema{type: :string, format: :binary}}},
        Responses.errors(
          Responses.author_read([
            {404, ["not_found"]},
            {409, ["download_too_large", "media_not_ready"]},
            {422, ["validation_failed"]},
            {429, ["checks_busy"]}
          ])
        )
      )

  # The zip and its staging directory come from
  # Espalier.Media.Store.staging_dir/0; the name follows the key format. The
  # send runs inside the slot of the download and ends at its deadline or at
  # the first block that the client does not take within the send timeout,
  # and the context removes the directory after it, also when the send
  # fails.
  def download(conn, %{id: id}) do
    Workbench.download(conn.assigns.current_scope, id, fn %{name: name, path: path} ->
      BlockDownload.send_download(conn, path,
        filename: name,
        content_type: "application/zip",
        min_rate: Workbench.download_min_bytes_per_second(),
        floor_ms: Workbench.download_floor_seconds() * 1_000
      )
    end)
  end
end
