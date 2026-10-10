defmodule Espalier.Catalog.Pack.Schema.Feedback do
  @moduledoc """
  The schema of `feedback.yaml`: `intro` and at least one question in
  `questions` (`Espalier.Catalog.Pack.Schema.Question`). The validator stores
  both in the `config` of the `feedback` station.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{Cast, Question}

  @primary_key false
  embedded_schema do
    field :intro, :string
    embeds_many :questions, Question
  end

  @type t :: %__MODULE__{}

  @doc "Casts the data of `feedback.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(feedback, attrs) do
    feedback
    |> Cast.cast(attrs, required: [:intro, :questions])
    |> Cast.validate_length(:questions, 1, "`questions` needs at least one question")
    |> Cast.validate_unique_by(:questions, :key)
  end
end
