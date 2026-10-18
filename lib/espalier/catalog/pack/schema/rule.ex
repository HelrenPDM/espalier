defmodule Espalier.Catalog.Pack.Schema.Rule do
  @moduledoc """
  An entry of `rules.yaml`: a rule of a module that pairs a statement with the action that follows from it.

  `modules/<directory>/rules.yaml` holds a list of entries. The file is
  optional; a module without it has no rules. An item refers to the rules that
  it practises by their `number` in the `rules` of `items.yaml`, and the
  feedback of the item returns those rules. The numbers are unique within the
  module, so two modules can both have a rule 1.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `number` | integer | yes | At least 1, at most 2147483647. Unique in the module. |
  | `statement` | string | yes | Not empty. The statement of the rule. |
  | `action` | string | yes | Not empty. The action that follows from the statement. |
  | `cite` | list of string | no | Each entry has the form `source-key#locator`, no entry twice. |

  A `cite` entry consists of the key of a source in `sources.yaml` (key
  format `^[a-z0-9][a-z0-9-]*$`), a hash sign and a locator. The locator is not
  empty, has at most 255 characters, starts and ends with a character that is
  no whitespace and holds no line feed. The validator checks across files that
  the source key exists in `sources.yaml`; the locator is free text, for
  example a chapter or a page.

  ## Example

  ```yaml
  - number: 1
    statement: Generated text follows likely wording and carries no check of its own.
    action: Treat every generated statement as a draft until you have checked it.
    cite: ["vendor-guide#Limitations"]
  - number: 2
    statement: A generated text is shared only after the release checks.
    action: Run the release checks and confirm them with your initials.
  ```

  The source `vendor-guide` of the first entry must exist in `sources.yaml` of
  the pack. The validator checks this reference across files, so the block is
  valid for this schema alone.

  ## Checks

  The schema reports:

    * `` `rules.yaml` must hold a list of entries `` when the file holds no list;
    * `` missing field `statement` ``, and the same for `number` and `action`;
    * `` `number` must be at least 1 `` and `` `number` must be an integer ``;
    * `` `cite` entry `x` does not have the form `source-key#locator` ``;
    * `` the locator of a `cite` entry must have at most 255 characters ``;
    * `` duplicate entry `x` in `cite` ``.

  The checks across files report:

    * `` duplicate rule number `1`, first used in `modules/<directory>/rules.yaml` at line 1 ``;
    * `` unknown source `x` in `cite` ``;
    * `` unknown rule `3` of this module in `rules` ``, at the item in `items.yaml` that names a number without a rule.

  ## See also

    * [Content packs](content-packs.md), the section on `rules.yaml`
    * `Espalier.Catalog.Pack.Schema.Source`, the `sources.yaml` that `cite` points to
    * `Espalier.Catalog.Pack.Schema.Item`, whose `rules` name rule numbers
    * `Espalier.Catalog.Pack.Schema.PackModule`, the `module.yaml` of the same module
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :number, :integer
    field :statement, :string
    field :action, :string
    field :cite, {:array, :string}
  end

  @typedoc "The cast contents of an entry of `rules.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `rules.yaml`.

  Returns a changeset that is valid when the entry follows the rules of the
  moduledoc.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(rule, attrs) do
    rule
    |> Cast.cast(attrs, required: [:number, :statement, :action])
    |> Cast.validate_min(:number, 1)
    |> Cast.validate_cite(:cite)
    |> Cast.validate_unique(:cite)
  end
end
