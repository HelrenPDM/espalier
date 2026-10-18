defmodule Espalier.Catalog.Pack.Schema.Lesson do
  @moduledoc """
  The front matter of a lesson file: its `title` and its `position` in the module.

  A lesson is one Markdown file `modules/<directory>/lessons/<key>.md`. Every
  module directory holds at least one lesson file, and the file name without
  `.md` is the lesson key. The key matches the key format
  `^[a-z0-9][a-z0-9-]*$` and has at most 255 characters. Other files of
  the same module refer to it: the `lesson` and `reveals` of an item and the
  `taught_in` of an objective name lesson keys of that module.

  A lesson file has three parts. A line `---` opens the front matter, which is
  a YAML mapping that this module casts. A second line `---` closes it. The
  body follows and holds the blocks that
  `Espalier.Catalog.Pack.Directives.split/2` separates and
  `Espalier.Catalog.Pack.Schema.Block` casts. The body holds at least one
  block.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `title` | string | yes | At most 255 characters. The title may hold glossary references (`[[term:slug]]`), which the validator resolves against `glossary.yaml`. |
  | `position` | integer | yes | At least 1, at most 2147483647. The position is unique among the lessons of the module. |

  Any other key in the front matter is an error.

  ## Example

  The front matter of `modules/01-basics/lessons/01-first-lesson.md` is this
  mapping, written between the two lines `---`:

  ```yaml
  title: What a language model does
  position: 1
  ```

  The complete file continues with the body of blocks:

  ```markdown
  ---
  title: What a language model does
  position: 1
  ---

  :::text{provenance=invented}
  A [[term:llm|language model]] continues text.
  :::

  :::explanation{collapsed_on=short provenance=sourced cite="vendor-guide#Overview"}
  The next word follows from probabilities learned in training.
  :::
  ```

  The reference `[[term:llm|language model]]` and the source key
  `vendor-guide` are checked across files, against `glossary.yaml` and
  `sources.yaml`.

  ## Checks

  The loader reports these errors of the file layout, at line 1 of the file
  unless the message names a line:

    * ``a lesson file starts with a front matter line `---` ``: the first line
      is not `---`;
    * ``the front matter is not closed by a line `---` ``;
    * ``lesson key `<key>` does not match the key format``: the file name
      without `.md` is no key.

  The validator reports these errors:

    * ``the front matter must hold a map``: the front matter is empty, a list
      or a scalar;
    * ``missing field `title` `` and ``missing field `position` ``, and
      `` `title` has no value `` when the field is present with `null`;
    * ``unknown field `<name>` ``;
    * `` `title` must be a string `` and `` `position` must be an integer ``;
      a quoted `"1"` is no integer, because values are not converted;
    * `` `title` must have at most 255 characters ``;
    * `` `position` must be at least 1 ``;
    * ``duplicate lesson position `<n>`, first used in `<file>` at line <line>``;
    * ``the lesson has no blocks`` and
      ``the lesson key must have at most 255 characters``.

  The conventions of all value types are in
  `Espalier.Catalog.Pack.Schema.Cast`.

  ## See also

    * [Content packs](content-packs.md), sections "Lesson files" and "Lesson directives"
    * `Espalier.Catalog.Pack.Directives` for the syntax of the body
    * `Espalier.Catalog.Pack.Schema.Block` for the attributes and values of a block
    * `Espalier.Catalog.Pack.Schema.Item` for `lesson` and `reveals`
    * `Espalier.Catalog.Pack.Schema.Objective` for `taught_in`
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :title, :string
    field :position, :integer
  end

  @typedoc "The front matter of a lesson file: `title` and `position`."
  @type t :: %__MODULE__{}

  @doc """
  Casts the front matter of a lesson file, a map with string keys.

  Returns an `Ecto.Changeset` that is valid when `title` and `position` are
  present and satisfy the rules of the moduledoc.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(lesson, attrs) do
    lesson
    |> Cast.cast(attrs, required: [:title, :position])
    |> Cast.validate_max_length(:title)
    |> Cast.validate_min(:position, 1)
  end
end
