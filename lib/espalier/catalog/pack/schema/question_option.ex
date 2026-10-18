defmodule Espalier.Catalog.Pack.Schema.QuestionOption do
  @moduledoc """
  An option of a `single_choice` question of `feedback.yaml`.

  The options are the entries of the `options` list of a question of kind `single_choice`, in the order of the list. A question needs at least two options.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the options of the question. |
  | `label` | string | yes | The text of the option. The schema sets no length limit. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  One option, as it stands in the `options` list of a question:

  ```yaml
  key: useful
  label: Useful
  ```

  ## Checks

    * "missing field `label`" and "`label` has no value" for a required field that is absent or `null`; the same for `key`.
    * "unknown field `name`" for a key that the table does not list.
    * "`key` value `Very Useful` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "duplicate key `useful` in `options`", reported by the question on the second option with that key.

  ## See also

  [Content packs](content-packs.md), section "`feedback.yaml`". The neighbor modules are `Espalier.Catalog.Pack.Schema.Question` (the question that holds the options) and `Espalier.Catalog.Pack.Schema.Feedback` (the file).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
  end

  @typedoc "The cast data of one option of a feedback question."
  @type t :: %__MODULE__{}

  @doc """
  Casts one option of a feedback question and returns a changeset whose
  errors `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(option, attrs) do
    option
    |> Cast.cast(attrs, required: [:key, :label])
    |> Cast.validate_key(:key)
  end
end
