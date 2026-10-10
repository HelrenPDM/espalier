defmodule Espalier.Catalog.Block do
  @moduledoc """
  A block of a lesson. `collapsed_on` lists the paths on which it starts
  collapsed, and a `placeholder` block names a policy in `placeholder_key`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Citation, Lesson}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blocks" do
    field :position, :integer

    field :kind, Ecto.Enum,
      values: [:text, :explanation, :example, :case_comparison, :quote, :callout, :placeholder]

    field :body, :string

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :collapsed_on, {:array, Ecto.Enum}, values: [:short, :full], default: []
    field :placeholder_key, :string

    belongs_to :lesson, Lesson
    has_many :citations, Citation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:position, :kind, :body, :provenance, :collapsed_on, :placeholder_key])
    |> validate_required([:position, :kind, :body, :provenance])
  end
end
