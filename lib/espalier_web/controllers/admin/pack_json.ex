defmodule EspalierWeb.Admin.PackJSON do
  @moduledoc """
  The views of `EspalierWeb.Admin.PackController` (task 0015, step 7).

  The pack view carries the report, the payload of a `validated` import
  (with answer keys; the route is restricted to authors) and `alignment`:
  `mode` and `matrix` from the stored payload (`nil` without one) and the
  report entries of `Espalier.Catalog.Alignment.check/1` with file and line,
  split into `errors` and `warnings`.

  `media` (task 0018, step 10) holds the media of the payload keyed by path
  with the state and the facts of their assets (`missing` for a deleted
  asset), and `media_policy` the media settings of the installation, which
  the preview applies.
  """

  alias Espalier.Catalog.{Alignment, PackImport}
  alias Espalier.Media
  alias Espalier.Media.Asset

  @finding_members ~w(file line check module key message)

  @doc "Renders an import."
  def show(%{pack_import: %PackImport{} = pack_import}) do
    report = pack_import.report || %{}
    errors = Map.get(report, "errors", [])
    warnings = Map.get(report, "warnings", [])
    payload = pack_import.payload

    %{
      id: pack_import.id,
      status: pack_import.status,
      pack_key: pack_import.pack_key,
      pack_version: pack_import.pack_version,
      inserted_at: pack_import.inserted_at,
      published_at: pack_import.published_at,
      report: %{errors: errors, warnings: warnings},
      payload: if(pack_import.status == :validated, do: payload),
      alignment: alignment(payload, report),
      media: media(payload),
      media_policy: Media.policy()
    }
  end

  @doc "The media of a payload keyed by path, with the state and facts of their assets."
  def media(%{} = payload) do
    entries = Map.get(payload, "media") || []
    assets = entries |> Enum.map(& &1["asset_id"]) |> Media.assets_by_id()

    Map.new(entries, fn entry ->
      {entry["path"], media_entry(entry, Map.get(assets, entry["asset_id"]))}
    end)
  end

  def media(_payload), do: %{}

  defp media_entry(entry, nil) do
    %{
      kind: entry["kind"],
      status: "missing",
      failure: nil,
      failure_detail: nil,
      url: nil,
      mime: nil,
      width: nil,
      height: nil,
      duration_ms: nil,
      progress: 0,
      has_audio: false,
      has_alpha: false,
      animated: false,
      poster_url: nil
    }
  end

  defp media_entry(_entry, %Asset{} = asset) do
    %{
      kind: asset.kind,
      status: asset.status,
      failure: asset.failure,
      failure_detail: asset.failure_detail,
      url: Media.url(asset),
      mime: Media.mime(Media.delivery_ext(asset.kind)),
      width: asset.width,
      height: asset.height,
      duration_ms: asset.duration_ms,
      progress: asset.progress,
      has_audio: asset.has_audio,
      has_alpha: asset.has_alpha,
      animated: asset.animated,
      poster_url: Media.poster_url(asset)
    }
  end

  @doc """
  The member `alignment` of the pack view and of the check of a draft of
  the pack workbench (task 0016a, step 6): `mode` and `matrix` from
  `payload` (`nil` without one) and the entries of `report` (a report of
  `Espalier.Catalog.Pack.Report.stored/2`) that carry `check`, split into
  `errors` and `warnings`.
  """
  def alignment(payload, report) when is_map(report) do
    %{
      mode: if(is_map(payload), do: payload["alignment"]),
      matrix: if(is_map(payload), do: Alignment.matrix(payload)),
      errors: findings(Map.get(report, "errors", [])),
      warnings: findings(Map.get(report, "warnings", []))
    }
  end

  @doc "Renders the 422 answer of a rejected archive."
  def archive_rejected(%{entries: entries}) do
    %{error: "archive_rejected", report: %{errors: entries, warnings: []}}
  end

  @doc "Renders the 409 answer `alignment_errors`."
  def alignment_errors(%{findings: findings}) do
    %{
      error: "alignment_errors",
      findings: Enum.map(findings, &Map.take(&1, [:check, :module, :file, :key, :message]))
    }
  end

  @doc "Renders the diff of `Espalier.Catalog.Pack.Diff.compute/1`."
  def diff(%{diff: diff}), do: diff

  # The report entries of the alignment checks are the ones with `check`.
  defp findings(entries) do
    for %{"check" => check} = entry when is_integer(check) <- entries,
        do: Map.take(entry, @finding_members)
  end
end
