defmodule Espalier.MediaFixtures do
  @moduledoc """
  Test helpers for the media library of task 0018 (step 23).

  `demo_media!/0` stores the media files of the demo pack as delivery files
  in the test store and inserts `ready` assets for them, so that a test
  imports and publishes the demo pack without ffmpeg and without the ingest
  lock: it passes the returned mapping as the option `media:` of the
  importer. The store is content-addressed, so a second call stores the
  same bytes at the same path; each call inserts new rows with a random
  `source_sha256`, so that the unique index never makes one sandbox
  transaction wait for another and a test may call it more than once. The
  rows carry the real digests of the files in `sha256`, so a pack that the
  pack writer exports from them imports into the same assets.

  `process_queued!/1` runs `Espalier.Media.process_now/1` on the queued
  assets of an import, for the tests that run the real ingest.
  """

  import Ecto.Query

  alias Espalier.Catalog.PackImport
  alias Espalier.Media
  alias Espalier.Media.{Asset, Store}
  alias Espalier.{PackFixtures, Repo}

  # The media of the demo pack with the facts of their delivery files.
  @demo_media [
    {"media/release-checks.svg", :svg, "svg", %{width: 720, height: 200}},
    {"media/assistant-demo.webm", :video, "webm",
     %{width: 640, height: 360, duration_ms: 8_008, has_audio: true}},
    {"media/assistant-demo-en.vtt", :captions, "vtt", %{duration_ms: 8_000}}
  ]

  @doc "The media paths of the demo pack."
  def demo_media_paths, do: Enum.map(@demo_media, &elem(&1, 0))

  @doc """
  Stores the media of the demo pack and inserts a `ready` asset per file.
  Returns the mapping `%{path => asset_id}` for the option `media:` of
  `Espalier.Catalog.Pack.Importer.import/3` and
  `Espalier.Catalog.import_pack/3`.
  """
  def demo_media!(dir \\ PackFixtures.demo_path()) do
    Map.new(@demo_media, fn {path, kind, ext, facts} ->
      asset = stored_asset!(Path.join(dir, path), kind, ext, facts, path)
      {path, asset.id}
    end)
  end

  @doc """
  The `media:` mapping for the pack at `path`: the mapping of
  `demo_media!/1` when the pack has a folder `media/` (the demo pack and its
  copies, which hold the same files), `%{}` otherwise. Within one test
  process every call returns the same mapping, as a second import of the
  same files on one installation finds the same assets.
  """
  def media_for(path) do
    cond do
      not File.dir?(Path.join(path, "media")) ->
        %{}

      mapping = Process.get({__MODULE__, :demo_media}) ->
        mapping

      true ->
        mapping = demo_media!(path)
        Process.put({__MODULE__, :demo_media}, mapping)
        mapping
    end
  end

  @doc """
  Copies `file` into the test store as a delivery file with `ext` and
  inserts a `ready` asset of `kind` with `facts` for it.
  """
  def stored_asset!(file, kind, ext, facts \\ %{}, source_name \\ nil) do
    {sha256, bytes} = Store.digest(file)
    target = Store.path(sha256, ext)
    File.mkdir_p!(Path.dirname(target))
    unless File.regular?(target), do: File.cp!(file, target)

    Repo.insert!(
      struct!(
        %Asset{
          kind: kind,
          status: :ready,
          title: Path.rootname(Path.basename(source_name || file)),
          source_name: Path.basename(source_name || file),
          source_sha256: random_sha256(),
          sha256: sha256,
          ext: ext,
          bytes: bytes,
          incoming_bytes: 0,
          progress: 100,
          origin: :pack
        },
        facts
      )
    )
  end

  @doc "A random lower-case hex digest of 64 characters."
  def random_sha256, do: 32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  @doc """
  Processes every queued asset of the media of `pack_import` in the calling
  process and returns the assets as they end.
  """
  def process_queued!(%PackImport{media_asset_ids: ids}) do
    from(a in Asset, where: a.id in ^ids and a.status == :queued)
    |> Repo.all()
    |> Enum.map(&Media.process_now/1)
  end

  ## Helpers of the context and worker tests

  @doc """
  Points `MEDIA_DIR` at a fresh directory below `System.tmp_dir!/0`, merges
  `overrides` into `config :espalier, :media`, and restores the setting and
  removes the directory when the test exits. Returns the directory. The
  modules that call it run synchronously, because the setting is global.
  """
  def media_env!(overrides \\ []) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "espalier-media-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    put_media_env!([dir: dir] ++ overrides)
    dir
  end

  @doc """
  Merges `overrides` into `config :espalier, :media` and restores the
  previous value when the test exits.
  """
  def put_media_env!(overrides) do
    previous = Application.get_env(:espalier, :media, [])
    Application.put_env(:espalier, :media, Keyword.merge(previous, overrides))
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:espalier, :media, previous) end)
    :ok
  end

  @doc """
  Inserts an asset row with `attrs` over the defaults of a `ready` SVG of
  origin `pack` with a random source and delivery digest; no file is
  written. `attrs` may set every field, `inserted_at` and `updated_at`
  included.
  """
  def insert_asset!(attrs \\ %{}) do
    Repo.insert!(
      struct!(
        %Asset{
          kind: :svg,
          status: :ready,
          title: "asset",
          source_name: "asset.svg",
          source_sha256: random_sha256(),
          sha256: random_sha256(),
          ext: "svg",
          bytes: 100,
          incoming_bytes: 0,
          progress: 100,
          origin: :pack
        },
        attrs
      )
    )
  end

  @doc """
  Writes `content` as a stored file of the test store under its digest with
  `ext` and returns the digest.
  """
  def store_file!(content, ext) do
    sha256 = :sha256 |> :crypto.hash(content) |> Base.encode16(case: :lower)
    target = Store.path(sha256, ext)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, content)
    sha256
  end

  @doc """
  The work directories of the runs of the jobs of the asset `asset_id`,
  `work/<asset id>-<run id>`, sorted. Every entry of `work/` whose name
  starts with the asset id counts.
  """
  def work_dirs(asset_id) do
    Store.work_root() |> Path.join(asset_id <> "*") |> Path.wildcard() |> Enum.sort()
  end

  @doc """
  A PNG of `width` by `height` pixels in one colour, with an alpha channel
  for `alpha: true`, encoded in the BEAM.
  """
  def png(width, height, opts \\ []) do
    alpha? = Keyword.get(opts, :alpha, false)
    {color_type, pixel} = if alpha?, do: {6, <<200, 40, 40, 128>>}, else: {2, <<200, 40, 40>>}
    row = <<0>> <> :binary.copy(pixel, width)

    png_chunks([
      {"IHDR", <<width::32, height::32, 8, color_type, 0, 0, 0>>},
      {"IDAT", :zlib.compress(:binary.copy(row, height))},
      {"IEND", ""}
    ])
  end

  @doc """
  A PNG whose header names `width` by `height` pixels, with an `IDAT` chunk
  of `data_bytes` zero bytes that no decoder can read; the detection reads
  only the header.
  """
  def png_header(width, height, data_bytes \\ 16) do
    png_chunks([
      {"IHDR", <<width::32, height::32, 8, 2, 0, 0, 0>>},
      {"IDAT", :binary.copy(<<0>>, data_bytes)},
      {"IEND", ""}
    ])
  end

  defp png_chunks(chunks) do
    for {type, data} <- chunks, into: <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> do
      <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
    end
  end

  @doc "A WebVTT file with one cue that holds `text`."
  def vtt(text \\ "A steady tone plays.") do
    "WEBVTT\n\n00:00.000 --> 00:01.500\n#{text}\n"
  end

  @doc "A WebVTT file with a `STYLE` block, which the captions check rejects."
  def vtt_with_style(text \\ "A steady tone plays.") do
    "WEBVTT\n\nSTYLE\n::cue { color: red }\n\n00:00.000 --> 00:01.500\n#{text}\n"
  end

  @doc """
  An SVG with a `text` element of `count` characters `>`, which the
  rebuild writes as `&gt;`, so the delivery file is `3 * count` bytes
  larger than the source. `label` makes sources of the same size distinct.
  """
  def growing_svg(count, label \\ "a") do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>#{label}</title><text>) <>
      String.duplicate(">", count) <> "</text></svg>"
  end
end
