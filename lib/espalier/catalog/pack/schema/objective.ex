defmodule Espalier.Catalog.Pack.Schema.Objective do
  @moduledoc """
  An entry of `objectives.yaml`: a learning objective of a module with its competence area, depth and phase.

  `modules/<directory>/objectives.yaml` holds a list of entries, one per
  learning objective of the module. The file is optional; a module without it
  has no objectives. Items (`objectives` in `items.yaml`) and companion formats
  (`objectives` in `formats.yaml`) refer to an objective by its `key`. Because
  the key is unique in the whole pack, an item of one module can name an
  objective of another module.

  An objective belongs to a topic, which is its module. Constructive alignment
  connects it to the lessons that teach it (`taught_in`) and to the items and
  formats that provide evidence for it. The alignment checks run on the
  objectives of every module, see "Alignment" below.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | string in the key format | yes | `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the pack. |
  | `statement` | string | yes | Not empty. The guides write it as a sentence of the form "Learners can ...". |
  | `area` | one of `subject`, `method`, `self`, `social` | yes | The competence area (the CORE areas). |
  | `depth` | one of `know`, `apply`, `judge` | yes | The depth of the competence. It selects the evidence kinds that fit. |
  | `phase` | one of `orient`, `understand`, `apply`, `anchor`, `update` | yes | The phase of the five-phase arc. |
  | `domain` | string in the key format | no | Must be an entry of `domains` in the `module.yaml` of the same module. |
  | `taught_in` | list of string in the key format | no | Lesson keys of the same module, no key twice. The alignment check needs at least one. |

  ## Example

  ```yaml
  - key: m1-subject-varying-answers
    statement: Learners can explain why the same prompt can produce different answers.
    area: subject
    depth: know
    phase: understand
    domain: drafting
    taught_in: [02-second-lesson]
  - key: m1-method-release-checks
    statement: Learners can run the release checks on a generated text and confirm them with their initials.
    area: method
    depth: apply
    phase: apply
    taught_in: [02-second-lesson, 03-third-lesson]
  ```

  The schema checks only the form of `domain` and `taught_in`. The validator
  resolves them against `domains` and the lessons of the module, as the checks
  below describe.

  ## Alignment

  `Espalier.Catalog.Alignment.check/1` runs after the file checks and reports
  these findings on objectives:

    * check 1: the objective has no entry in `taught_in`, or it has no evidence;
    * check 4: the objective has evidence, but no piece of it has a kind that
      fits the depth.

  Evidence for an objective is every item that names it and is listed by an
  assessment, every other item that names it and has a correct answer (every
  kind except `poll`), and every format with `attendance_counts: true` that
  names it. The kinds that fit a depth are:

  | Depth | Evidence kinds that fit |
  |---|---|
  | `know` | `single_choice`, `multiple_choice` |
  | `apply` | `slot_builder`, `classification`, `checklist_drill` |
  | `judge` | `classification_with_case_comparison`, `format` |

  A `classification` item also counts as `classification_with_case_comparison`
  when a lesson in `taught_in` holds a `case_comparison` block. With the default
  `alignment: strict` in `pack.yaml`, check 1 is an error and check 4 a warning;
  with `alignment: warn`, both are warnings. Each module also needs at least one
  objective in each of the four areas, or an `areas_elsewhere` entry for the
  area (check 3, see `Espalier.Catalog.Pack.Schema.AreasElsewhere`).

  ## Checks

  The schema reports:

    * `` `objectives.yaml` must hold a list of entries `` when the file holds no list, and `an entry must be a map` when an entry is no mapping;
    * `` unknown field `x` `` and `` missing field `x` ``;
    * `` `area` must be one of `subject`, `method`, `self`, `social` ``, `` `depth` must be one of `know`, `apply`, `judge` `` and `` `phase` must be one of `orient`, `understand`, `apply`, `anchor`, `update` ``;
    * `` `key` value `M1_Next` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``, and the same message for `domain` and for an entry of `taught_in`;
    * `` duplicate entry `x` in `taught_in` ``.

  The checks across files report:

    * `` duplicate objective key `x`, first used in `modules/<directory>/objectives.yaml` at line 1 ``;
    * `` unknown lesson `x` of this module in `taught_in` ``;
    * `` `domain` `x` is not one of the module's `domains` ``, also when the module lists no `domains`.

  The alignment check reports `` objective `x` names no teaching lesson in `taught_in` `` and `` objective `x` has no evidence `` (the second message continues with the list of what could name the objective), and for check 4 a message that lists the evidence kinds found and the kinds that fit the depth.

  ## See also

    * [Content packs](content-packs.md), the section "Constructive alignment"
    * `Espalier.Catalog.Alignment`, the alignment checks and the alignment matrix
    * `Espalier.Catalog.Pack.Schema.PackModule`, which defines `domains`
    * `Espalier.Catalog.Pack.Schema.Item` and `Espalier.Catalog.Pack.Schema.Format`, which name objectives in `objectives`
    * `Espalier.Catalog.Pack.Schema.AreasElsewhere`, for areas without an objective in the module
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :key, :string
    field :statement, :string
    field :area, Ecto.Enum, values: [:subject, :method, :self, :social]
    field :depth, Ecto.Enum, values: [:know, :apply, :judge]
    field :phase, Ecto.Enum, values: @phases
    field :domain, :string
    field :taught_in, {:array, :string}
  end

  @typedoc "The cast contents of an entry of `objectives.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `objectives.yaml`.

  Returns a changeset that is valid when the entry follows the rules of the
  moduledoc.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(objective, attrs) do
    objective
    |> Cast.cast(attrs, required: [:key, :statement, :area, :depth, :phase])
    |> Cast.validate_key(:key)
    |> Cast.validate_key(:domain)
    |> Cast.validate_keys(:taught_in)
    |> Cast.validate_unique(:taught_in)
  end
end
