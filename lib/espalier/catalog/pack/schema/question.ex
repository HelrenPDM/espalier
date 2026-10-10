defmodule Espalier.Catalog.Pack.Schema.Question do
  @moduledoc """
  A question of `feedback.yaml`: `key`, `kind` (`single_choice`, `scale` for
  the values 1 to 5, or `free_text`), `label`, and for `single_choice` at
  least two `options` (`Espalier.Catalog.Pack.Schema.QuestionOption`). The
  other kinds have no options.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, QuestionOption}

  @primary_key false
  embedded_schema do
    field :key, :string
    field :kind, Ecto.Enum, values: [:single_choice, :scale, :free_text]
    field :label, :string
    embeds_many :options, QuestionOption
  end

  @type t :: %__MODULE__{}

  @doc "Casts a question of `feedback.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(question, attrs) do
    question
    |> Cast.cast(attrs, required: [:key, :kind, :label])
    |> Cast.validate_key(:key)
    |> Cast.validate_unique_by(:options, :key)
    |> validate_options()
  end

  defp validate_options(changeset) do
    present? = Map.has_key?(changeset.params || %{}, "options")
    count = changeset |> get_field(:options) |> List.wrap() |> length()

    case get_field(changeset, :kind) do
      :single_choice when count < 2 and present? ->
        Cast.add(changeset, :options, "a `single_choice` question needs at least two options")

      :single_choice when count < 2 ->
        Cast.add_entry_error(changeset, "a `single_choice` question needs at least two options")

      kind when kind in [:scale, :free_text] and present? ->
        Cast.add(changeset, :options, "a `#{kind}` question has no options")

      _ ->
        changeset
    end
  end
end
