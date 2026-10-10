defmodule Espalier.Catalog.Pack.Schema.QuestionOption do
  @moduledoc "An option of a `single_choice` question of `feedback.yaml`: `key` and `label`."
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts an option of a feedback question."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(option, attrs) do
    option
    |> Cast.cast(attrs, required: [:key, :label])
    |> Cast.validate_key(:key)
  end
end
