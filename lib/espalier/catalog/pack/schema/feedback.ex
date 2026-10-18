defmodule Espalier.Catalog.Pack.Schema.Feedback do
  @moduledoc """
  The `feedback.yaml` file: the introduction and the questions of the feedback station.

  `feedback.yaml` sits in the pack directory and holds one mapping. The file is optional. When it exists, `stations.yaml` needs exactly one station of kind `feedback`, and without the file it must have none. The station takes `intro` and `questions` from this file, so its own `config` names neither. The normalized pack stores both in the `config` of the `feedback` station.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `intro` | string | yes | The text above the questions. The schema sets no length limit. |
  | `questions` | list of mappings | yes | At least one question, each cast by `Espalier.Catalog.Pack.Schema.Question`. The `key` of every question is unique in the list. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  ```yaml
  intro: Your answers help to improve this program.
  questions:
    - key: usefulness
      kind: single_choice
      label: How useful was the program for your work?
      options:
        - key: useful
          label: Useful
        - key: not-useful
          label: Not useful
    - key: clarity
      kind: scale
      label: How clear were the lessons, from 1 (unclear) to 5 (very clear)?
    - key: suggestion
      kind: free_text
      label: What should the program change?
  ```

  ## Checks

    * "`feedback.yaml` must hold a map" when the file holds anything else, which includes an empty file.
    * "missing field `questions`" and "`questions` has no value" for a required field that is absent or `null`; the same for `intro`.
    * "unknown field `name`" for a key that the table does not list.
    * "`questions` needs at least one question" for an empty list.
    * "`questions` must be a list" and "entries of `questions` must be maps".
    * "duplicate key `usefulness` in `questions`" on the second question with that key.
    * The errors of the questions and their options, which `Espalier.Catalog.Pack.Schema.Question` and `Espalier.Catalog.Pack.Schema.QuestionOption` list.
    * Across files: "the pack needs a `feedback` station, because `feedback.yaml` exists", "a `feedback` station needs `feedback.yaml`" and "the pack has one `feedback` station only", and "the `feedback` station takes `intro` from `feedback.yaml`" (likewise for `questions`) for an `intro` or `questions` key in the `config` of the station.

  ## See also

  [Content packs](content-packs.md), section "`feedback.yaml`". The neighbor modules are `Espalier.Catalog.Pack.Schema.Question`, `Espalier.Catalog.Pack.Schema.QuestionOption`, `Espalier.Catalog.Pack.Schema.Station` (the `feedback` station) and `Espalier.Catalog.Pack.Validator` (the cross-file checks).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{Cast, Question}

  @primary_key false
  embedded_schema do
    field :intro, :string
    embeds_many :questions, Question
  end

  @typedoc "The cast data of `feedback.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts the mapping of `feedback.yaml` with its questions and returns a
  changeset whose errors `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists
  with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(feedback, attrs) do
    feedback
    |> Cast.cast(attrs, required: [:intro, :questions])
    |> Cast.validate_length(:questions, 1, "`questions` needs at least one question")
    |> Cast.validate_unique_by(:questions, :key)
  end
end
