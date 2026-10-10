defmodule Espalier.Catalog.Segment do
  @moduledoc "A segment of the self-assessment station with its default path."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "segments" do
    field :key, :string
    field :label, :string
    field :description, :string
    field :default_path, Ecto.Enum, values: [:short, :full]
    field :position, :integer
    field :archived_at, :utc_datetime

    belongs_to :program, Program

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(segment, attrs) do
    segment
    |> cast(attrs, [:key, :label, :description, :default_path, :position])
    |> validate_required([:key, :label, :description, :default_path, :position])
  end
end
