defmodule Espalier.Workbench.PackDraftMedia do
  @moduledoc """
  A media entry of a workbench draft (task 0018, step 3): a `media/` path of
  the draft and the library asset at that path. The draft holds no copy of
  the file; the check writes an empty file at the path, the import links
  the path to the asset, and the download places the delivery file there.

  `changeset/2` casts `path` only; `Espalier.Workbench` sets the draft and
  the asset on the struct. A row keeps its asset from deletion
  (`on_delete: :restrict`), and a missing asset answers `not_found` through
  the foreign key constraint.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Media.Asset
  alias Espalier.Workbench.PackDraft

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pack_draft_media" do
    field :path, :string
    belongs_to :pack_draft, PackDraft
    belongs_to :media_asset, Asset

    timestamps(type: :utc_datetime)
  end

  @doc "The changeset of a new media entry or of a new path."
  def changeset(%__MODULE__{} = media, attrs) do
    media
    |> cast(attrs, [:path])
    |> validate_required([:path])
    |> unique_constraint([:pack_draft_id, :path])
    |> foreign_key_constraint(:media_asset_id)
  end
end
