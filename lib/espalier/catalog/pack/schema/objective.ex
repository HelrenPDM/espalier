defmodule Espalier.Catalog.Pack.Schema.Objective do
  @moduledoc """
  An entry of `modules/<directory>/objectives.yaml`, a learning objective:
  `key`, `statement`, `area` (`subject`, `method`, `self` or `social`),
  `depth` (`know`, `apply` or `judge`), `phase`, the optional `domain` (one of
  the module's `domains`) and `taught_in` (lesson keys of the module).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :key, :string
    field :statement, :string
    field :area, Ecto.Enum, values: [:subject, :method, :self, :social]
    field :depth, Ecto.Enum, values: [:know, :apply, :judge]
    field :phase, Ecto.Enum, values: @phases
    field :domain, :string
    field :taught_in, {:array, :string}
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `objectives.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(objective, attrs) do
    objective
    |> Cast.cast(attrs, required: [:key, :statement, :area, :depth, :phase])
    |> Cast.validate_key(:key)
    |> Cast.validate_key(:domain)
    |> Cast.validate_keys(:taught_in)
    |> Cast.validate_unique(:taught_in)
  end
end
