defmodule Espalier.Catalog.Pack.Schema.ClassificationCategory do
  @moduledoc """
  An element of `categories`: a category that a `classification` item sorts
  its cases into.

  Categories sit in the list `categories` of the `config` of a
  `classification` item (`Espalier.Catalog.Pack.Schema.ClassificationConfig`).
  The `expected` mapping of the config refers to a category by its `key`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique among the categories of the item. |
  | `label` | string | yes | The name of the category. A non-empty string. |

  ## Example

  ```yaml
  - key: assistant-may-draft
    label: The assistant may draft it
  - key: keep-it
    label: I keep it
  ```

  ## Checks

    * `` unknown field `x` `` and `` missing field `label` `` (also for `key`);
    * `` `label` must not be empty `` for a blank string;
    * `` `key` value `X` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` duplicate key `x` in `categories` `` and `` `categories` needs at least
      two categories `` from the config;
    * `` `expected` maps the case `x` to an unknown category `` when a value of
      `expected` is no category key.

  ## See also

  [Content packs](content-packs.md), section "Item kinds". The module
  `Espalier.Catalog.Pack.Schema.ClassificationConfig` holds the categories.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
  end

  @typedoc "A category, as cast from an element of `categories`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an element of `categories`.

  Returns an `Ecto.Changeset`.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(category, attrs) do
    category
    |> Cast.cast(attrs, required: [:key, :label])
    |> Cast.validate_key(:key)
  end
end
