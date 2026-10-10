defmodule Espalier.Catalog.Item do
  @moduledoc """
  A practice or exam item. It has no area and no level of its own; it
  reaches both through the learning objectives it names (`item_objectives`).

  `config` holds the kind-specific data: `slots` for `slot_builder`,
  `categories`, `cases` and `expected` for `classification`, and `checks`
  for `checklist_drill`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{
    Assessment,
    AssessmentItem,
    Citation,
    LearningObjective,
    Lesson,
    Option,
    Program,
    Rule
  }

  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "items" do
    field :key, :string

    field :kind, Ecto.Enum,
      values: [
        :single_choice,
        :multiple_choice,
        :slot_builder,
        :classification,
        :checklist_drill,
        :poll
      ]

    field :stem, :string
    field :core, :boolean, default: false
    field :phase, Ecto.Enum, values: [:orient, :understand, :apply, :anchor, :update]

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :config, :map, default: %{}
    field :position, :integer
    field :archived_at, :utc_datetime

    belongs_to :program, Program
    belongs_to :module, CatalogModule
    belongs_to :lesson, Lesson
    has_many :options, Option
    has_many :citations, Citation
    many_to_many :rules, Rule, join_through: "item_rules"

    many_to_many :reveals, Lesson,
      join_through: "item_reveals",
      join_keys: [item_id: :id, lesson_id: :id]

    many_to_many :objectives, LearningObjective, join_through: "item_objectives"
    many_to_many :assessments, Assessment, join_through: AssessmentItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:key, :kind, :stem, :core, :phase, :provenance, :config, :position])
    |> validate_required([:key, :kind, :stem, :core, :phase, :provenance, :position])
  end
end
