defmodule EspalierWeb.Admin.PackDraftMediaController do
  @moduledoc """
  The media entries of a draft of the pack workbench (task 0018, step 16;
  README section 8, row "Pack workbench").

  Every change runs in `:author_write`, so it needs a second factor from
  the last 10 minutes (README section 6.4), and sends the `lock_version` of
  the draft it starts from, as the file routes of task 0016a do; this
  controller renders the 409 answer `stale_draft` itself. An image, SVG or
  video asset becomes a media entry at a `media/` path with the delivery
  extension of the asset; a `ready` captions asset becomes a text file of
  the draft at a `.vtt` path, so the browser never reads the file through
  `/media/`. The answers are the draft: 422 `validation_failed` with
  `fields.path` `["invalid_path"]` or `fields.media_asset_id`
  `["not_ready"]`, 404 `not_found` for an unknown draft, entry or asset,
  and 409 `path_taken`, `too_many_files`, `media_limit` or
  `draft_too_large`.
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

  @media_id [
    media_id: [
      in: :path,
      required: true,
      description: "The id of the media entry.",
      schema: Fields.uuid()
    ]
  ]

  @limits "A media entry names a `media/` path with at most three directories and the " <>
            "delivery extension of its asset (`webp`, `svg`, `webm`). A draft holds at most " <>
            "500 media entries and at most 2,000 files and media entries together. A " <>
            "captions asset becomes a text file at a `.vtt` path within the limits of the " <>
            "files of a draft."

  @conflicts {"Error codes: `stale_draft` (with `lock_version`), `path_taken`, " <>
                "`too_many_files`, `media_limit`, `draft_too_large`", "application/json",
              Admin.StaleDraft}

  @change_errors Responses.errors(
                   Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
                 )

  operation :create,
    summary: "Add a library asset to a draft",
    description: @limits,
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The asset and its path", "application/json", Admin.DraftMediaAttach, required: true},
    responses:
      Map.merge(
        %{201 => {"The draft", "application/json", Admin.PackDraft}, 409 => @conflicts},
        @change_errors
      )

  def create(conn, %{id: id}) do
    %{media_asset_id: asset_id, path: path, lock_version: lock_version} = conn.body_params

    conn.assigns.current_scope
    |> Workbench.attach_media(id, %{media_asset_id: asset_id, path: path}, lock_version)
    |> respond(conn, :created)
  end

  operation :rename,
    summary: "Move a media entry to another path",
    description: @limits,
    security: Responses.session_and_csrf(),
    parameters: @id ++ @media_id,
    request_body: {"The new path", "application/json", Admin.DraftMediaRename, required: true},
    responses:
      Map.merge(
        %{200 => {"The draft", "application/json", Admin.PackDraft}, 409 => @conflicts},
        @change_errors
      )

  def rename(conn, %{id: id, media_id: media_id}) do
    %{path: path, lock_version: lock_version} = conn.body_params

    conn.assigns.current_scope
    |> Workbench.rename_media(id, media_id, path, lock_version)
    |> respond(conn, :ok)
  end

  operation :delete,
    summary: "Remove a media entry from a draft",
    description: "The asset stays in the media library.",
    security: Responses.session_and_csrf(),
    parameters:
      @id ++
        @media_id ++
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

  def delete(conn, %{id: id, media_id: media_id, lock_version: lock_version}) do
    conn.assigns.current_scope
    |> Workbench.delete_media(id, media_id, lock_version)
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
