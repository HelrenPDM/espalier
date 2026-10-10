defmodule Espalier.Catalog.LearningObjective do
  @moduledoc """
  A learning objective of a module (README section 7, domain rule 14): a
  statement in one CORE competence area, with a depth and a phase. It is
  taught in lessons (`objective_lessons`), and items (`item_objectives`) and
  companion formats (`format_objectives`) name it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{CompanionFormat, Item, Lesson, Program}
  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "learning_objectives" do
    field :key, :string
    field :statement, :string
    field :area, Ecto.Enum, values: [:subject, :method, :self, :social]
    field :depth, Ecto.Enum, values: [:know, :apply, :judge]
    field :phase, Ecto.Enum, values: [:orient, :understand, :apply, :anchor, :update]
    field :domain, :string
    field :position, :integer
    field :archived_at, :utc_datetime

    belongs_to :program, Program
    belongs_to :module, CatalogModule

    many_to_many :lessons, Lesson, join_through: "objective_lessons"
    many_to_many :items, Item, join_through: "item_objectives"
    many_to_many :companion_formats, CompanionFormat, join_through: "format_objectives"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(learning_objective, attrs) do
    learning_objective
    |> cast(attrs, [:key, :statement, :area, :depth, :phase, :domain, :position])
    |> validate_required([:key, :statement, :area, :depth, :phase, :position])
  end
end
