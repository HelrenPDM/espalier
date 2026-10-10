defmodule Espalier.Catalog.Lesson do
  @moduledoc "A lesson of a module. Its key is the file name of the lesson without `.md`."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Block, Item, LearningObjective}
  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "lessons" do
    field :key, :string
    field :position, :integer
    field :title, :string
    field :archived_at, :utc_datetime

    belongs_to :module, CatalogModule
    has_many :blocks, Block
    has_many :items, Item

    many_to_many :objectives, LearningObjective,
      join_through: "objective_lessons",
      join_keys: [lesson_id: :id, learning_objective_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lesson, attrs) do
    lesson
    |> cast(attrs, [:key, :position, :title])
    |> validate_required([:key, :position, :title])
  end
end
