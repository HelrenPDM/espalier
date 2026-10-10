defmodule Espalier.Catalog.CompanionFormat do
  @moduledoc """
  A companion format held outside the platform. A format with
  `attendance_counts: true` provides evidence for the objectives it names;
  any other format anchors them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{LearningObjective, Program}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "companion_formats" do
    field :key, :string
    field :title, :string
    field :description, :string

    field :phases, {:array, Ecto.Enum},
      values: [:orient, :understand, :apply, :anchor, :update],
      default: []

    field :attendance_counts, :boolean, default: false
    field :position, :integer
    field :archived_at, :utc_datetime

    belongs_to :program, Program
    many_to_many :objectives, LearningObjective, join_through: "format_objectives"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(companion_format, attrs) do
    companion_format
    |> cast(attrs, [:key, :title, :description, :phases, :attendance_counts, :position])
    |> validate_required([:key, :title, :description, :attendance_counts, :position])
  end
end
