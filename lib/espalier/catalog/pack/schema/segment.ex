defmodule Espalier.Catalog.Pack.Schema.Segment do
  @moduledoc """
  An entry of `segments.yaml`: an answer of the self-assessment station that preselects a path.

  `segments.yaml` sits in the pack directory and holds a list of entries. The file is optional. The station of kind `self_assessment` offers the segments as answers, and the `default_path` of the chosen segment preselects the path of the learner. The path names correspond to the values of `collapsed_on` of a block. The order of the entries is the order of the answers. When the file has entries, `stations.yaml` needs exactly one station of kind `self_assessment`; without entries, it must have none.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the file (checked across files). |
  | `label` | string | yes | The answer that the learner chooses, at most 255 characters. |
  | `description` | string | yes | The text below the answer. The schema sets no length limit. |
  | `default_path` | one of `short`, `full` | yes | The path that the segment preselects. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  ```yaml
  - key: regular-users
    label: I use a writing assistant every week
    description: You know the assistant and want to check your routine.
    default_path: short
  - key: new-users
    label: I have not used a writing assistant yet
    description: You want to learn how the assistant works before you start.
    default_path: full
  ```

  ## Checks

    * "`segments.yaml` must hold a list of entries" when the file holds anything else, which includes an empty file.
    * "missing field `default_path`" and "`default_path` has no value" for a required field that is absent or `null`; the same for `key`, `label` and `description`.
    * "unknown field `name`" for a key that the table does not list.
    * "`key` value `Regular Users` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "`label` must have at most 255 characters".
    * "`default_path` must be one of `short`, `full`".
    * Across files: "duplicate segment key `regular-users`, first used in `segments.yaml` at line 1".
    * Across files: "the pack needs a `self_assessment` station, because `segments.yaml` has entries", "a `self_assessment` station needs entries in `segments.yaml`" and "the pack has one `self_assessment` station only".

  ## See also

  [Content packs](content-packs.md), section "`segments.yaml`". The neighbor modules are `Espalier.Catalog.Pack.Schema.Station` (the `self_assessment` station), `Espalier.Catalog.Pack.Schema.Block` (the `collapsed_on` paths) and `Espalier.Catalog.Pack.Validator` (the cross-file checks).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :label, :string
    field :description, :string
    field :default_path, Ecto.Enum, values: [:short, :full]
  end

  @typedoc "The cast data of one entry of `segments.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `segments.yaml` and returns a changeset whose errors
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(segment, attrs) do
    segment
    |> Cast.cast(attrs, required: [:key, :label, :description, :default_path])
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:label)
  end
end
