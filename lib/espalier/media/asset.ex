defmodule Espalier.Media.Asset do
  @moduledoc """
  A file of the media library (task 0018, step 3): an image, an SVG, a video
  or a captions file, from an upload or from a content pack.

  Media are course content and belong to no learner record: `created_by_id`
  names the uploader, as `audit_events.actor_id` names an actor, and becomes
  `nil` when that account is deleted. An upload or an import with an actor
  that restarts a failed asset makes that actor the uploader. The table
  holds no encrypted and no keyed-hash column.

  `changeset/2` casts `title` only. `Espalier.Media` alone sets kind,
  status, failure, digests, sizes, facts, origin and `created_by_id` on the
  struct or in its queries (ASVS 15.3.3).

  `source_sha256` is the digest of the uploaded or imported file, `sha256`
  the digest of the delivery file and `poster_sha256` the digest of the
  poster of a video or an animated image. Two assets may share a delivery
  file or a poster: two sources can convert to the same bytes. `width` and
  `height` describe the delivery file, and a poster has the same size.
  `incoming_bytes` counts the file that waits for processing, so that the
  storage quota covers it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @failures [
    :too_many_pixels,
    :too_many_frames,
    :too_long,
    :no_video_stream,
    :unsupported_animation,
    :invalid_svg,
    :invalid_captions,
    :malware_found,
    :scan_failed,
    :storage_full,
    :conversion_failed,
    :timeout,
    :interrupted
  ]

  # The reason tags of the animated WebP check, the SVG rebuild and the
  # captions check (step 6) and of the scan (step 7).
  @failure_details [
    :structure,
    :first_frame,
    :too_many_frames,
    :too_large,
    :encoding,
    :doctype,
    :entity,
    :processing_instruction,
    :parse_error,
    :root,
    :embedded_image,
    :css,
    :animation,
    :nul,
    :header,
    :too_many_cues,
    :timing,
    :style,
    :limits_exceeded,
    :size_limit,
    :timeout,
    :closed,
    :connect,
    :reply
  ]

  @max_title 255

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "media_assets" do
    field :kind, Ecto.Enum, values: [:image, :svg, :video, :captions]
    field :status, Ecto.Enum, values: [:queued, :processing, :ready, :failed]
    field :failure, Ecto.Enum, values: @failures
    field :failure_detail, Ecto.Enum, values: @failure_details
    field :title, :string
    field :source_name, :string
    field :source_sha256, :string
    field :sha256, :string
    field :ext, :string
    field :bytes, :integer
    field :width, :integer
    field :height, :integer
    field :duration_ms, :integer
    field :has_audio, :boolean, default: false
    field :animated, :boolean, default: false
    field :has_alpha, :boolean, default: false
    field :poster_sha256, :string
    field :poster_bytes, :integer
    field :incoming_bytes, :integer, default: 0
    field :progress, :integer, default: 0
    field :origin, Ecto.Enum, values: [:upload, :pack]
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc "The failure codes of step 8."
  @spec failures() :: [atom()]
  def failures, do: @failures

  @doc "The reason tags of steps 6 and 7."
  @spec failure_details() :: [atom()]
  def failure_details, do: @failure_details

  @doc "The largest title in characters (code points, as PostgreSQL counts them)."
  @spec max_title() :: pos_integer()
  def max_title, do: @max_title

  @doc """
  The changeset of a title change: 1 to 255 characters without U+0000. The
  length counts code points, as the varchar(255) column does, so a letter
  with a combining accent counts twice.
  """
  def changeset(%__MODULE__{} = asset, attrs) do
    asset
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: @max_title, count: :codepoints)
    |> validate_change(:title, fn :title, title ->
      if String.contains?(title, <<0>>), do: [title: "must not contain U+0000"], else: []
    end)
  end
end
