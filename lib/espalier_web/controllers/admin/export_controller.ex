defmodule EspalierWeb.Admin.ExportController do
  @moduledoc """
  The SCORM export of a published module for the role `author` (task 0016,
  step 10; README section 8, row "Exports").

  `POST /api/admin/exports` runs in `:author_write`, so the request needs a
  second factor from the last 10 minutes (README section 6.4), and passes
  only `module_id` and `scorm_version` of its schema to
  `Espalier.Interop.request_export/3` (ASVS 15.3.3). It answers 202 with
  the export in status `queued`; a module that is unknown, archived or part
  of a program that is not published answers 404.

  The two GET routes run in `:author`. The download builds the file path
  from `EXPORT_DIR` and the stored `file_name` only
  (`Espalier.Interop.package_path/1`), so no request parameter names a file
  (ASVS 5.3.2 and 5.4.1), and `Phoenix.Controller.send_download/3` encodes
  the generated name `<program slug>-module-<number>-<scorm_version>.zip`
  for `content-disposition` (ASVS 5.4.2). While the export is `queued`,
  `running` or `failed`, the download answers 409 `export_not_ready`, which
  this controller renders itself. An export that the retention of
  `Espalier.Interop.prune_exports/1` deleted has no row, so both GET routes
  answer 404.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Interop
  alias EspalierWeb.Admin.ExportJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: exports"]

  @id [id: [in: :path, required: true, description: "The export id.", schema: Fields.uuid()]]

  operation :create,
    summary: "Request the SCORM export of a module",
    description:
      "Queues the export in the Oban queue `exports` and answers 202. The package " <>
        "contains the answer keys of the module.",
    security: Responses.session_and_csrf(),
    request_body: {"The export", "application/json", Admin.ExportRequest, required: true},
    responses:
      Map.merge(
        %{202 => {"The queued export", "application/json", Admin.Export}},
        Responses.errors(
          Responses.author_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def create(conn, _params) do
    %{module_id: module_id, scorm_version: scorm_version} = conn.body_params

    with {:ok, export} <-
           Interop.request_export(conn.assigns.current_scope, module_id, scorm_version) do
      conn
      |> put_status(:accepted)
      |> put_resp_header("location", ~p"/api/admin/exports/#{export.id}")
      |> json(ExportJSON.show(%{export: export}))
    end
  end

  operation :show,
    summary: "Read an export",
    description: "`download_path` is set once the status is `done`.",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The export", "application/json", Admin.Export}},
        Responses.errors(
          Responses.author_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, export} <- Interop.get_export(conn.assigns.current_scope, id) do
      json(conn, ExportJSON.show(%{export: export}))
    end
  end

  operation :download,
    summary: "Download the package of an export",
    description:
      "Sends the zip with the file name `<program slug>-module-<number>-<scorm_version>.zip`.",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{
          200 => {"The SCORM package", "application/zip", %Schema{type: :string, format: :binary}}
        },
        Responses.errors(
          Responses.author_read([
            {404, ["not_found"]},
            {409, ["export_not_ready"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def download(conn, %{id: id}) do
    with {:ok, export} <- Interop.get_export(conn.assigns.current_scope, id),
         {:ok, path} <- Interop.package_path(export) do
      send_package(conn, path, Interop.download_name(export))
    else
      {:error, :export_not_ready} ->
        conn |> put_status(:conflict) |> json(%{error: "export_not_ready"})

      {:error, _reason} = error ->
        error
    end
  end

  # `path` comes from Espalier.Interop.package_path/1, which joins EXPORT_DIR
  # and the stored basename `<id>.zip`; no request parameter names the file.
  # sobelow_skip ["Traversal.SendDownload"]
  defp send_package(conn, path, file_name) do
    send_download(conn, {:file, path}, filename: file_name, content_type: "application/zip")
  end
end
