defmodule Espalier.Catalog.Pack.Schema.Question do
  @moduledoc """
  A question of `feedback.yaml`: a single choice, a scale from 1 to 5 or a free text.

  The questions are the entries of the `questions` list of `feedback.yaml`, in the order of the list. The `kind` decides which other fields a question may have. A question of kind `single_choice` has a list of `options`, and the kinds `scale` and `free_text` have none.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the questions of the file. |
  | `kind` | one of `single_choice`, `scale`, `free_text` | yes | `single_choice` offers the `options`, `scale` offers the values 1 to 5, and `free_text` takes an open answer. |
  | `label` | string | yes | The text of the question. The schema sets no length limit. |
  | `options` | list of mappings | for kind `single_choice` | At least two options, each cast by `Espalier.Catalog.Pack.Schema.QuestionOption`. The `key` of every option is unique in the question. Not allowed on the kinds `scale` and `free_text`. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  A question of kind `single_choice` with its options:

  ```yaml
  key: usefulness
  kind: single_choice
  label: How useful was the program for your work?
  options:
    - key: useful
      label: Useful
    - key: not-useful
      label: Not useful
  ```

  A question of kind `scale` has no `options`:

  ```yaml
  key: clarity
  kind: scale
  label: How clear were the lessons, from 1 (unclear) to 5 (very clear)?
  ```

  ## Checks

    * "missing field `kind`" and "`kind` has no value" for a required field that is absent or `null`; the same for `key` and `label`.
    * "unknown field `name`" for a key that the table does not list.
    * "`kind` must be one of `single_choice`, `scale`, `free_text`".
    * "`key` value `Usefulness` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "a `single_choice` question needs at least two options", at `options` when the field is present and on the question when it is absent.
    * "a `scale` question has no options" and "a `free_text` question has no options" when `options` is present, also as an empty list.
    * "duplicate key `useful` in `options`" on the second option with that key.
    * "`options` must be a list" and "entries of `options` must be maps".

  ## See also

  [Content packs](content-packs.md), section "`feedback.yaml`". The neighbor modules are `Espalier.Catalog.Pack.Schema.Feedback` (the file) and `Espalier.Catalog.Pack.Schema.QuestionOption` (the options).
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

  @typedoc "The cast data of one question of `feedback.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one question of `feedback.yaml` with its options and returns a
  changeset whose errors `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists
  with their paths.
  """
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
