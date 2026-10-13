defmodule EspalierWeb.Admin.PackDraftFileController do
  @moduledoc """
  The files of a draft of the pack workbench for the role `author` (task
  0016a, step 9; README section 8, row "Pack workbench").

  The read runs in `:author`, and every change in `:author_write`, so it
  needs a second factor from the last 10 minutes (README section 6.4).
  Each change sends the `lock_version` of the draft it starts from;
  `Espalier.Workbench` applies it under a row lock on the draft and answers
  409 `stale_draft` with the stored version when another change came first,
  which this controller renders itself. The context checks every path
  against the path rules and every content against the content rules
  before it stores them (ASVS 2.2.1, 5.2.2 and 5.3.2): 422
  `validation_failed` with `fields.path` `["invalid_path"]` or
  `fields.content` `["too_large"]` or `["nul_character"]`, and 409
  `path_taken`, `too_many_files` or `draft_too_large`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Workbench
  alias EspalierWeb.Admin.PackDraftJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: pack workbench"]

  @id [id: [in: :path, required: true, description: "The draft id.", schema: Fields.uuid()]]

  @file_id [
    file_id: [in: :path, required: true, description: "The file id.", schema: Fields.uuid()]
  ]

  @limits "A path names a file of the pack layout: a top-level YAML file (`pack.yaml`, " <>
            "`sources.yaml`, `glossary.yaml`, `segments.yaml`, `stations.yaml`, " <>
            "`feedback.yaml`, `qualifications.yaml`, `formats.yaml`), " <>
            "`modules/<dir>/{module,objectives,rules,items,assessment}.yaml` or " <>
            "`modules/<dir>/lessons/<key>.md`. A content is UTF-8 text without U+0000 of " <>
            "at most 1,048,576 bytes. A draft holds at most 2,000 files and at most five " <>
            "times `PACK_UPLOAD_MAX_MB` (default 20) in total."

  @conflicts {"Error codes: `stale_draft` (with `lock_version`), `path_taken`, " <>
                "`too_many_files`, `draft_too_large`", "application/json", Admin.StaleDraft}

  @change_errors Responses.errors(
                   Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
                 )

  operation :show,
    summary: "Read a file of a draft with its content",
    security: Responses.session(),
    parameters: @id ++ @file_id,
    responses:
      Map.merge(
        %{200 => {"The file", "application/json", Admin.PackDraftFile}},
        Responses.errors(
          Responses.author_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id, file_id: file_id}) do
    with {:ok, draft, file} <- Workbench.get_file(conn.assigns.current_scope, id, file_id) do
      json(conn, PackDraftJSON.file(%{draft: draft, file: file}))
    end
  end

  operation :create,
    summary: "Add a file to a draft",
    description: @limits,
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"The file", "application/json", Admin.PackDraftFileRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The draft", "application/json", Admin.PackDraft}, 409 => @conflicts},
        @change_errors
      )

  def create(conn, %{id: id}) do
    %{path: path, content: content, lock_version: lock_version} = conn.body_params

    conn.assigns.current_scope
    |> Workbench.create_file(id, %{path: path, content: content}, lock_version)
    |> respond(conn, :created)
  end

  operation :update,
    summary: "Save the content of a file",
    description: @limits,
    security: Responses.session_and_csrf(),
    parameters: @id ++ @file_id,
    request_body: {"The content", "application/json", Admin.PackDraftFileUpdate, required: true},
    responses:
      Map.merge(
        %{200 => {"The draft", "application/json", Admin.PackDraft}, 409 => @conflicts},
        @change_errors
      )

  def update(conn, %{id: id, file_id: file_id}) do
    %{content: content, lock_version: lock_version} = conn.body_params

    conn.assigns.current_scope
    |> Workbench.update_file(id, file_id, content, lock_version)
    |> respond(conn, :ok)
  end

  operation :rename,
    summary: "Rename a file",
    description: @limits,
    security: Responses.session_and_csrf(),
    parameters: @id ++ @file_id,
    request_body: {"The new path", "application/json", Admin.PackDraftRename, required: true},
    responses:
      Map.merge(
        %{200 => {"The draft", "application/json", Admin.PackDraft}, 409 => @conflicts},
        @change_errors
      )

  def rename(conn, %{id: id, file_id: file_id}) do
    %{path: path, lock_version: lock_version} = conn.body_params

    conn.assigns.current_scope
    |> Workbench.rename_file(id, file_id, path, lock_version)
    |> respond(conn, :ok)
  end

  operation :delete,
    summary: "Delete a file",
    security: Responses.session_and_csrf(),
    parameters:
      @id ++
        @file_id ++
        [
          lock_version: [
            in: :query,
            required: true,
            description: "The `lock_version` of the draft that the change starts from.",
            schema: %Schema{type: :integer, minimum: 1}
          ]
        ],
    responses:
      Map.merge(
        %{
          200 => {"The draft", "application/json", Admin.PackDraft},
          409 => {"Error code: `stale_draft`", "application/json", Admin.StaleDraft}
        },
        @change_errors
      )

  def delete(conn, %{id: id, file_id: file_id, lock_version: lock_version}) do
    conn.assigns.current_scope
    |> Workbench.delete_file(id, file_id, lock_version)
    |> respond(conn, :ok)
  end

  defp respond({:ok, draft}, conn, status) do
    conn
    |> put_status(status)
    |> json(PackDraftJSON.show(%{draft: draft}))
  end

  defp respond({:error, {:stale_draft, current}}, conn, _status) do
    conn
    |> put_status(:conflict)
    |> json(PackDraftJSON.stale_draft(%{lock_version: current}))
  end

  defp respond({:error, _reason} = error, _conn, _status), do: error
end
