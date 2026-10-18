defmodule Espalier.Catalog.ProgramMedia do
  @moduledoc """
  A media file of a published program (task 0018, step 3): a `media/` path
  of the payload of its import and the library asset at that path. The
  publisher replaces the rows of a program in the transaction of a publish,
  and a row keeps its asset from deletion (`on_delete: :restrict`).

  The media route serves a file to a learner only when a row of a published
  program names its asset (ASVS 8.2.2).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "program_media" do
    field :path, :string
    field :program_id, :binary_id
    field :media_asset_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(program_media, attrs) do
    program_media
    |> cast(attrs, [:path])
    |> validate_required([:path])
    |> unique_constraint([:program_id, :path])
    |> foreign_key_constraint(:media_asset_id)
  end
end
