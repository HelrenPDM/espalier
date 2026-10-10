defmodule Espalier.Catalog.Pack.Schema.Assessment do
  @moduledoc """
  An entry of `modules/<directory>/assessment.yaml`: `key`, `title`, `kind`
  (`practice` or `exam`), `counts_for_credential`, `max_wrong` (at least 0),
  `core_required` and `items`, at least one item key of the module, each
  once, in order. An exam allows at most one wrong answer less than it has
  items.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :title, :string
    field :kind, Ecto.Enum, values: [:practice, :exam]
    field :counts_for_credential, :boolean
    field :max_wrong, :integer
    field :core_required, :boolean
    field :items, {:array, :string}
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `assessment.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(assessment, attrs) do
    assessment
    |> Cast.cast(attrs,
      required: [:key, :title, :kind, :counts_for_credential, :max_wrong, :core_required, :items]
    )
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_min(:max_wrong, 0)
    |> Cast.validate_length(:items, 1, "`items` needs at least one item")
    |> Cast.validate_keys(:items)
    |> Cast.validate_unique(:items)
    |> validate_exam_max_wrong()
  end

  defp validate_exam_max_wrong(changeset) do
    items = changeset |> get_field(:items) |> List.wrap()
    max_wrong = get_field(changeset, :max_wrong)

    if get_field(changeset, :kind) == :exam and items != [] and is_integer(max_wrong) and
         max_wrong > length(items) - 1,
       do:
         Cast.add(
           changeset,
           :max_wrong,
           "`max_wrong` of an exam with #{length(items)} items must be between 0 and #{length(items) - 1}"
         ),
       else: changeset
  end
end
