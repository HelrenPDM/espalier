defmodule Espalier.Catalog.Pack.Schema.GlossaryTerm do
  @moduledoc """
  An entry of `glossary.yaml`: `slug`, `label` and `short_text`. Markdown
  refers to it as `[[term:slug]]` or `[[term:slug|label]]`.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :slug, :string
    field :label, :string
    field :short_text, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `glossary.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(term, attrs) do
    term
    |> Cast.cast(attrs, required: [:slug, :label, :short_text])
    |> Cast.validate_key(:slug)
    |> Cast.validate_max_length(:label)
  end
end
