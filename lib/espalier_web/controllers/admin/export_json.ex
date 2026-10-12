defmodule EspalierWeb.Admin.ExportJSON do
  @moduledoc """
  The view of `EspalierWeb.Admin.ExportController` (task 0016, step 10):
  the export with its module and program, and the download path while the
  status is `done`.
  """
  use EspalierWeb, :verified_routes

  alias Espalier.Interop.Export

  @doc "Renders an export with its program and its module."
  def show(%{export: %Export{program: program, module: module} = export}) do
    %{
      id: export.id,
      module: %{
        id: module.id,
        number: module.number,
        title: module.title,
        program: %{slug: program.slug, title: program.title}
      },
      scorm_version: export.scorm_version,
      status: export.status,
      error: export.error,
      inserted_at: export.inserted_at,
      download_path: if(export.status == :done, do: ~p"/api/admin/exports/#{export.id}/download")
    }
  end
end
