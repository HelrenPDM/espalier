defmodule Espalier.Catalog.Program do
  @moduledoc """
  A program: the published content of one content pack. `slug` is the `key`
  of `pack.yaml`, and `pack_version` its `version`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{
    Assessment,
    CompanionFormat,
    GlossaryTerm,
    Item,
    LearningObjective,
    Qualification,
    Segment,
    Source,
    Station
  }

  alias Espalier.Catalog.Module, as: CatalogModule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "programs" do
    field :slug, :string
    field :title, :string
    field :locale, :string
    field :status, Ecto.Enum, values: [:draft, :published, :archived], default: :draft
    field :pack_version, :string

    has_many :modules, CatalogModule
    has_many :stations, Station
    has_many :segments, Segment
    has_many :qualifications, Qualification
    has_many :companion_formats, CompanionFormat
    has_many :glossary_terms, GlossaryTerm
    has_many :sources, Source
    has_many :learning_objectives, LearningObjective
    has_many :items, Item
    has_many :assessments, Assessment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(program, attrs) do
    program
    |> cast(attrs, [:slug, :title, :locale, :status, :pack_version])
    |> validate_required([:slug, :title, :locale, :status, :pack_version])
    |> unique_constraint(:slug)
  end
end
