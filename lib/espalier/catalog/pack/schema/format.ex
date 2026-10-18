defmodule Espalier.Catalog.Pack.Schema.Format do
  @moduledoc """
  An entry of `formats.yaml`: a companion format outside the platform.

  `formats.yaml` sits in the pack directory and holds a list of entries. The
  file is optional. Other parts of the pack refer to a format by its `key`:
  an `attendance` requirement of a qualification
  (`Espalier.Catalog.Pack.Schema.Requirement`) as `target`, and the
  `areas_elsewhere` of a module (`Espalier.Catalog.Pack.Schema.AreasElsewhere`)
  as `where: format:<key>`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | `^[a-z0-9][a-z0-9-]*$`, at most 255 characters, unique in the file. |
  | `title` | string | yes | At most 255 characters. |
  | `description` | string | yes | No length limit is checked. |
  | `phases` | list of one of `orient`, `understand`, `apply`, `anchor`, `update` | no | No entry appears twice. |
  | `attendance_counts` | boolean | yes | `true` or `false`. With `true`, an `attendance` requirement can point to the format, and the format provides evidence for the objectives that it names. With `false`, the format anchors those objectives and provides no evidence. |
  | `objectives` | list of key | no | Keys of objectives of the pack (checked across files). Each entry is in the key format and has at most 255 characters, and no entry appears twice. |

  ## Example

  ```yaml
  - key: team-session
    title: Team session
    description: A session in which a team agrees how the use of a writing assistant is marked in shared texts.
    phases: [anchor]
    attendance_counts: true
    objectives: [m1-social-mark-use]
  - key: reference-card
    title: Reference card
    description: A printable card with the release checks.
    phases: [anchor, update]
    attendance_counts: false
    objectives: [m1-method-release-checks]
  ```

  Each entry is valid on its own. The validator checks across files that the
  objectives `m1-social-mark-use` and `m1-method-release-checks` are defined
  in the `objectives.yaml` of a module.

  ## Checks

  Errors of the schema:

    * "missing field `key`", likewise for `title`, `description` and
      `attendance_counts`.
    * "`key` value `x` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "`title` must have at most 255 characters".
    * "`attendance_counts` must be `true` or `false`".
    * "`phases` must be a list" and "entries of `phases` must be one of
      `orient`, `understand`, `apply`, `anchor`, `update`".
    * "duplicate entry `x` in `phases`", likewise for `objectives`.
    * "`objectives` value `x` does not match the key format
      `^[a-z0-9][a-z0-9-]*$`".
    * "unknown field `x`" for a key that the table does not list.

  Errors of the validator, which runs after the schema stage reports no error:

    * "duplicate format key `x`, first used in `formats.yaml` at line N".
    * "unknown objective `x` in `objectives`".
    * "unknown format `x` in `target`" and "the format `x` in `target` has
      `attendance_counts: false`" at an `attendance` requirement that points to
      the format.
    * "unknown format `x` in `where`" at an `areas_elsewhere` entry of a module.

  ## See also

  [Content packs](content-packs.md), sections "`formats.yaml`" and "Objectives
  of items and formats", and the neighbor modules
  `Espalier.Catalog.Pack.Schema.Requirement` (the `attendance` target),
  `Espalier.Catalog.Pack.Schema.AreasElsewhere` (`where: format:<key>`),
  `Espalier.Catalog.Pack.Schema.Objective` (the objectives that `objectives`
  names) and `Espalier.Catalog.Pack.Validator` (the cross-file checks).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :key, :string
    field :title, :string
    field :description, :string
    field :phases, {:array, Ecto.Enum}, values: @phases
    field :attendance_counts, :boolean
    field :objectives, {:array, :string}
  end

  @typedoc "A cast entry of `formats.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an entry of `formats.yaml` and returns the changeset.

  The errors carry the path of the offending value, which
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` returns.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(format, attrs) do
    format
    |> Cast.cast(attrs, required: [:key, :title, :description, :attendance_counts])
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_unique(:phases)
    |> Cast.validate_keys(:objectives)
    |> Cast.validate_unique(:objectives)
  end
end
