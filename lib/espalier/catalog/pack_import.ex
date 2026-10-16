defmodule Espalier.Catalog.PackImport do
  @moduledoc """
  An import of a content pack. `report` holds the `errors` and `warnings` of
  the validator, and `payload` the normalized map of a `validated` import.
  `imported_by_id` holds the id of the importing user, or `nil` for the mix
  tasks and the release function; it has no foreign key. `media_asset_ids`
  holds the asset ids of `payload["media"]` (task 0018), so that the uses of
  an asset need no scan of the payloads.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pack_imports" do
    field :pack_key, :string
    field :pack_version, :string
    field :status, Ecto.Enum, values: [:validated, :failed, :published]
    field :report, :map
    field :payload, :map
    field :published_at, :utc_datetime
    field :imported_by_id, Ecto.UUID
    field :media_asset_ids, {:array, :binary_id}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pack_import, attrs) do
    pack_import
    |> cast(attrs, [:pack_key, :pack_version, :status, :report, :payload, :media_asset_ids])
    |> validate_required([:status, :report])
  end
end
