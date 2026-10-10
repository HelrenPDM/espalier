defmodule Espalier.Catalog.GlossaryTerm do
  @moduledoc "A glossary entry that Markdown references as `[[term:slug]]`."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "glossary_terms" do
    field :slug, :string
    field :label, :string
    field :short_text, :string
    field :archived_at, :utc_datetime

    belongs_to :program, Program

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(glossary_term, attrs) do
    glossary_term
    |> cast(attrs, [:slug, :label, :short_text])
    |> validate_required([:slug, :label, :short_text])
  end
end
