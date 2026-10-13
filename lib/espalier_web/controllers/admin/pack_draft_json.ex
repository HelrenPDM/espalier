defmodule EspalierWeb.Admin.PackDraftJSON do
  @moduledoc """
  The views of `EspalierWeb.Admin.PackDraftController` and
  `EspalierWeb.Admin.PackDraftFileController` (task 0016a, step 9).

  A draft carries its usage against the limits of `Espalier.Workbench`, and
  the single view its files without content. The file view carries the
  content and the `lock_version` of its draft. The check carries the
  `lock_version` it checked, the report and the alignment of
  `EspalierWeb.Admin.PackJSON.alignment/2`, so that the pack view and the
  check share one implementation.
  """

  alias Espalier.Workbench
  alias Espalier.Workbench.{PackDraft, PackDraftFile}
  alias EspalierWeb.Admin.PackJSON

  @doc "Renders the list of drafts."
  def index(%{drafts: drafts}), do: %{data: Enum.map(drafts, &summary/1)}

  @doc "Renders a draft with its files."
  def show(%{draft: %PackDraft{} = draft}) do
    Map.put(summary(draft), :files, Enum.map(draft.files, &file_entry/1))
  end

  @doc "Renders the draft of an upload with the skipped paths of the archive."
  def upload(%{draft: %PackDraft{} = draft, skipped: skipped}) do
    Map.put(show(%{draft: draft}), :skipped, %{paths: skipped.paths, omitted: skipped.omitted})
  end

  @doc "Renders a file with its content and the `lock_version` of its draft."
  def file(%{draft: %PackDraft{} = draft, file: %PackDraftFile{} = file}) do
    %{
      id: file.id,
      path: file.path,
      content: file.content,
      bytes: file.bytes,
      updated_at: file.updated_at,
      lock_version: draft.lock_version
    }
  end

  @doc "Renders a check."
  def check(%{check: %{lock_version: lock_version, report: report, payload: payload}}) do
    %{
      lock_version: lock_version,
      report: %{errors: Map.get(report, "errors", []), warnings: Map.get(report, "warnings", [])},
      alignment: PackJSON.alignment(payload, report)
    }
  end

  @doc "Renders the 409 answer `stale_draft` with the stored `lock_version`."
  def stale_draft(%{lock_version: lock_version}),
    do: %{error: "stale_draft", lock_version: lock_version}

  defp summary(%PackDraft{} = draft) do
    %{
      id: draft.id,
      title: draft.title,
      pack_key: draft.pack_key,
      lock_version: draft.lock_version,
      inserted_at: draft.inserted_at,
      updated_at: draft.updated_at,
      usage: %{files: draft.file_count || 0, bytes: draft.bytes || 0},
      limits: %{
        files: Workbench.max_files(),
        file_bytes: Workbench.max_file_bytes(),
        draft_bytes: Workbench.max_draft_bytes()
      }
    }
  end

  defp file_entry(%PackDraftFile{} = file) do
    %{id: file.id, path: file.path, bytes: file.bytes, updated_at: file.updated_at}
  end
end
