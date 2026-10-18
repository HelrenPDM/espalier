defmodule Espalier.Catalog.Pack.Schema.GlossaryTerm do
  @moduledoc """
  An entry of `glossary.yaml`: a term that texts refer to as `[[term:slug]]`.

  `glossary.yaml` sits in the pack directory and holds a list of entries. The file is optional. Every string of every YAML file of the pack and every block body of a lesson may refer to a term as `[[term:slug]]`, or as `[[term:slug|label]]` with a label that is shown in that place. The slug in the reference has at most 255 characters and the label at most 1,000. The validator checks the references in every string. The player renders a reference as a button that carries the `short_text` of the term as its description and leads to the glossary entry in the texts that it formats as Markdown (lesson blocks, rules, station introductions). A reference in a plain-text field, such as the label of a question, appears literally. The terms are stored per program and are unique by `slug`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `slug` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the file (checked across files). Every reference `[[term:slug]]` must name a `slug` of this file. |
  | `label` | string | yes | The term as shown to the learner, at most 255 characters. |
  | `short_text` | string | yes | The short explanation. The schema sets no length limit. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  The file holds a list. References to these slugs are checked across files, so the block holds none.

  ```yaml
  - slug: prompt
    label: prompt
    short_text: The text you give an assistant to describe what it should do.
  - slug: source-check
    label: source check
    short_text: The comparison of a generated statement with a reliable source before the statement is used.
  ```

  ## Checks

    * "`glossary.yaml` must hold a list of entries" when the file holds anything else, which includes an empty file.
    * "missing field `short_text`" and "`short_text` has no value" for a required field that is absent or `null`; the same for `slug` and `label`.
    * "unknown field `name`" for a key that the table does not list.
    * "`slug` value `Source Check` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "`label` must have at most 255 characters".
    * Across files: "duplicate glossary slug `prompt`, first used in `glossary.yaml` at line 1".
    * Across files: "unknown glossary term `prompt` in `[[term:prompt]]`" for a reference to a slug that the file does not define, "empty label in `[[term:prompt| ]]`" for a blank label, and "malformed glossary reference `[[term:`" for an opening `[[term:` that no complete reference follows. The scan covers the strings of this file as well.

  ## See also

  [Content packs](content-packs.md), section "`glossary.yaml`", and its section on values for the reference syntax. The neighbor modules are `Espalier.Catalog.Pack.Schema.Source` and `Espalier.Catalog.Pack.Validator` (the cross-file checks).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :slug, :string
    field :label, :string
    field :short_text, :string
  end

  @typedoc "The cast data of one entry of `glossary.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `glossary.yaml` and returns a changeset whose errors
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(term, attrs) do
    term
    |> Cast.cast(attrs, required: [:slug, :label, :short_text])
    |> Cast.validate_key(:slug)
    |> Cast.validate_max_length(:label)
  end
end
