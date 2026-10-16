defmodule EspalierWeb.Admin.MediaJSON do
  @moduledoc """
  The views of the media library (task 0018, step 15): the asset view of
  `EspalierWeb.Admin.MediaController`, of the media entries of a draft and
  of the pack view, and the 409 answers `asset_in_use` and
  `media_not_ready`. A view carries no file path of the store and no
  digest of the source.
  """

  alias Espalier.Media
  alias Espalier.Media.Asset

  @doc "Renders a page of the library."
  def index(%{items: items, next: next}), do: %{items: Enum.map(items, &asset/1), next: next}

  @doc "Renders an asset with its uses."
  def show(%{asset: %Asset{} = asset, uses: uses}), do: Map.put(asset(asset), :uses, uses(uses))

  @doc "Renders an asset."
  def asset(%Asset{} = asset) do
    %{
      id: asset.id,
      kind: asset.kind,
      status: asset.status,
      failure: asset.failure,
      failure_detail: asset.failure_detail,
      progress: asset.progress,
      title: asset.title,
      source_name: asset.source_name,
      origin: asset.origin,
      ext: asset.ext,
      bytes: asset.bytes,
      width: asset.width,
      height: asset.height,
      duration_ms: asset.duration_ms,
      has_audio: asset.has_audio,
      animated: asset.animated,
      has_alpha: asset.has_alpha,
      url: Media.url(asset),
      poster_url: Media.poster_url(asset),
      inserted_at: asset.inserted_at,
      updated_at: asset.updated_at
    }
  end

  @doc "Renders the uses of an asset."
  def uses(%{programs: programs, drafts: drafts, imports: imports}) do
    %{
      programs: Enum.map(programs, &Map.take(&1, [:slug, :title])),
      drafts: Enum.map(drafts, &Map.take(&1, [:id, :title, :path])),
      imports: Enum.map(imports, &Map.take(&1, [:id, :pack_key, :inserted_at]))
    }
  end

  @doc "Renders the 409 answer `asset_in_use`."
  def asset_in_use(%{uses: uses}), do: %{error: "asset_in_use", uses: uses(uses)}

  @doc "Renders the 409 answer `media_not_ready` with the entries that are not `ready`."
  def media_not_ready(%{entries: entries}) do
    %{
      error: "media_not_ready",
      media:
        Enum.map(entries, fn entry ->
          %{path: entry["path"], status: entry["status"], failure: entry["failure"]}
        end)
    }
  end
end
