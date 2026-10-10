defmodule Espalier.Catalog.Module do
  @moduledoc """
  A module, the topic of constructive alignment (README section 7, domain
  rule 14). `areas_elsewhere` maps a competence area that the module's own
  objectives leave out to a map with `where` and `reason`.

  `alias Espalier.Catalog.Module` hides Elixir's `Module`, so other modules
  alias it with `as: CatalogModule`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Assessment, Item, LearningObjective, Lesson, Program, Rule}

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "modules" do
    field :number, :integer
    field :title, :string
    field :summary, :string
    field :phases, {:array, Ecto.Enum}, values: @phases, default: []
    field :domains, {:array, :string}, default: []
    field :single_path, :boolean, default: false
    field :refresher_unit, :boolean, default: false
    field :areas_elsewhere, :map, default: %{}
    field :archived_at, :utc_datetime

    belongs_to :program, Program
    has_many :lessons, Lesson
    has_many :learning_objectives, LearningObjective
    has_many :rules, Rule
    has_many :items, Item
    has_many :assessments, Assessment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(module, attrs) do
    module
    |> cast(attrs, [
      :number,
      :title,
      :summary,
      :phases,
      :domains,
      :single_path,
      :refresher_unit,
      :areas_elsewhere
    ])
    |> validate_required([:number, :title, :summary, :single_path, :refresher_unit])
  end
end
