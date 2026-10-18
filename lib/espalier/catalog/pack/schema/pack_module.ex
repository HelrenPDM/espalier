defmodule Espalier.Catalog.Pack.Schema.PackModule do
  @moduledoc """
  The `module.yaml` of a module: its number, title, summary, phases, domains, two flags and the areas covered elsewhere.

  `modules/<directory>/module.yaml` holds one mapping. It is the only YAML file
  that every module directory must hold; a missing file is the error `missing
  file`. The files `objectives.yaml`, `rules.yaml`, `items.yaml` and
  `assessment.yaml` of the same directory are optional, and the `lessons/`
  directory needs at least one lesson file.

  The `number` identifies the module in the pack. A station of kind `module`
  (`stations.yaml`), a requirement of kind `module_completed`
  (`qualifications.yaml`) and `module:<number>` in `areas_elsewhere` refer to
  it. The name of the directory carries no meaning of its own, but it must
  match the key format `^[a-z0-9][a-z0-9-]*$`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `number` | integer | yes | At least 1, at most 2147483647. Unique in the pack. |
  | `title` | string | yes | Not empty, at most 255 characters. |
  | `summary` | string | yes | Not empty. |
  | `phases` | list of `orient`, `understand`, `apply`, `anchor` or `update` | no | No value twice. The phases of the five-phase arc. |
  | `domains` | list of string | no | Each entry in the key format and at most 255 characters, no entry twice. The objectives of the module name one of them in `domain`. |
  | `single_path` | boolean | yes | `true` or `false`. With `true`, the module ignores the path of the learner. |
  | `refresher_unit` | boolean | yes | `true` or `false`. Marks the module that a qualification with `refresher_mode: update_unit` uses as its refresher. |
  | `areas_elsewhere` | mapping | no | The competence areas that the objectives of the module leave out, each with the place that covers it. See `Espalier.Catalog.Pack.Schema.AreasElsewhere`. |

  A field that the table does not list is an error. A required field that is
  absent or has the value `null` is an error. A value does not change its type:
  the string `"1"` is no integer, and the string `"true"` is no boolean.

  ## Example

  A module whose objectives cover the four competence areas needs no
  `areas_elsewhere`:

  ```yaml
  number: 1
  title: Working with a writing assistant
  summary: How a writing assistant produces text, how to prompt it and check its draft, and which tasks stay with you.
  phases: [orient, understand, apply, anchor]
  domains: [drafting, research]
  single_path: false
  refresher_unit: false
  ```

  A module that leaves out competence areas names the place that covers them.
  The validator resolves each `where` against the formats and modules of the
  whole pack, so this schema checks only its form:

  ```yaml
  number: 2
  title: Checking the output
  summary: How to judge a generated draft and release it after the release checks.
  phases: [apply, anchor, update]
  domains: []
  single_path: true
  refresher_unit: true
  areas_elsewhere:
    self:
      where: format:workshop
      reason: The workshop practises deciding which of one's own tasks an assistant may support.
    social:
      where: format:workshop
      reason: The workshop practises agreeing in a team how the use of an assistant is made visible.
  ```

  ## Checks

  The schema reports these errors for `module.yaml`:

    * `` `module.yaml` must hold a map `` when the file holds no mapping;
    * `` unknown field `x` `` and `` missing field `x` ``;
    * `` `number` must be at least 1 ``, `` `number` must be at most 2147483647 `` and `` `number` must be an integer ``;
    * `` `title` must have at most 255 characters ``;
    * `` duplicate entry `x` in `phases` `` and the same message for `domains`;
    * `` entries of `phases` must be one of `orient`, `understand`, `apply`, `anchor`, `update` ``;
    * `` `domains` value `Drafting` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``;
    * `` `single_path` must be `true` or `false` ``, and the same for `refresher_unit`.

  The checks across files report:

    * `` duplicate module number `1`, first used in `modules/<directory>/module.yaml` at line 1 ``;
    * `` module directory name `x` does not match the key format ``;
    * the errors for `where` that `Espalier.Catalog.Pack.Schema.Elsewhere` lists;
    * `` `refresher_mode: update_unit` needs a module with `refresher_unit: true` ``, reported at the qualification when no module sets the flag.

  The alignment check (`Espalier.Catalog.Alignment.check/1`) reports a
  competence area that neither an objective of the module nor
  `areas_elsewhere` covers. It places the finding at the line of the area in
  `areas_elsewhere`, or at line 1 of `module.yaml` when `areas_elsewhere` does
  not name the area.

  ## See also

    * [Content packs](content-packs.md), the long-form reference of the pack format
    * [Course YAML](course-yaml.md), the introduction to the YAML files of a course
    * `Espalier.Catalog.Pack.Schema.AreasElsewhere` and `Espalier.Catalog.Pack.Schema.Elsewhere`, the `areas_elsewhere` mapping
    * `Espalier.Catalog.Pack.Schema.Objective`, `Espalier.Catalog.Pack.Schema.Rule`, `Espalier.Catalog.Pack.Schema.Item` and `Espalier.Catalog.Pack.Schema.Assessment`, the other files of a module directory
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{AreasElsewhere, Cast}

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :number, :integer
    field :title, :string
    field :summary, :string
    field :phases, {:array, Ecto.Enum}, values: @phases
    field :domains, {:array, :string}
    field :single_path, :boolean
    field :refresher_unit, :boolean
    embeds_one :areas_elsewhere, AreasElsewhere
  end

  @typedoc "The cast contents of a `module.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts the mapping of a `module.yaml`.

  Returns a changeset that is valid when the data follows the rules of the
  moduledoc.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(module, attrs) do
    module
    |> Cast.cast(attrs, required: [:number, :title, :summary, :single_path, :refresher_unit])
    |> Cast.validate_min(:number, 1)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_unique(:phases)
    |> Cast.validate_keys(:domains)
    |> Cast.validate_unique(:domains)
  end
end
