defmodule Espalier.Catalog.Assessment do
  @moduledoc """
  A practice set or an exam of a module. The items and their order live in
  `assessment_items` (`Espalier.Catalog.AssessmentItem`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{AssessmentItem, Item, Program}
  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "assessments" do
    field :key, :string
    field :title, :string
    field :kind, Ecto.Enum, values: [:practice, :exam]
    field :counts_for_credential, :boolean, default: false
    field :max_wrong, :integer
    field :core_required, :boolean, default: false
    field :archived_at, :utc_datetime

    belongs_to :program, Program
    belongs_to :module, CatalogModule
    has_many :assessment_items, AssessmentItem
    many_to_many :items, Item, join_through: AssessmentItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(assessment, attrs) do
    assessment
    |> cast(attrs, [:key, :title, :kind, :counts_for_credential, :max_wrong, :core_required])
    |> validate_required([
      :key,
      :title,
      :kind,
      :counts_for_credential,
      :max_wrong,
      :core_required
    ])
  end
end
