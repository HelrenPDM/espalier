defmodule Espalier.Catalog.Pack.Schema.Rule do
  @moduledoc """
  An entry of `modules/<directory>/rules.yaml`: `number` (at least 1),
  `statement`, `action` and an optional `cite` (`source-key#locator`
  strings).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :number, :integer
    field :statement, :string
    field :action, :string
    field :cite, {:array, :string}
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `rules.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(rule, attrs) do
    rule
    |> Cast.cast(attrs, required: [:number, :statement, :action])
    |> Cast.validate_min(:number, 1)
    |> Cast.validate_cite(:cite)
    |> Cast.validate_unique(:cite)
  end
end
