defmodule Espalier.Catalog.Pack.Schema.Requirement do
  @moduledoc """
  A requirement of a qualification: one condition for its credential.

  A requirement has no file of its own. It is an element of the `requirements`
  list of a qualification (`Espalier.Catalog.Pack.Schema.Qualification`), and
  it names its object by `kind` and `target`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `kind` | one of `module_completed`, `assessment_passed`, `policy_acknowledged`, `attendance`, `qualification_held` | yes | Decides the type of `target`. |
  | `target` | integer or key | yes | An integer from 1 to 2147483647 for `module_completed`. A string in the key format `^[a-z0-9][a-z0-9-]*$` of at most 255 characters for every other kind. |

  The target by kind:

  | Kind | `target` | Checked across files |
  |---|---|---|
  | `module_completed` | The module number, as a YAML integer. | The pack has a module with that number. |
  | `assessment_passed` | The key of an assessment. | The assessment exists and has kind `exam`. |
  | `policy_acknowledged` | The key of a policy. | Not checked. The validator does not resolve the key. |
  | `attendance` | The key of a format of `formats.yaml`. | The format exists and has `attendance_counts: true`. |
  | `qualification_held` | The code of a qualification of the pack. | The qualification exists, and the `qualification_held` requirements of the pack form no cycle. A qualification that requires itself is a cycle. |

  A qualification holds each pair of `kind` and `target` once.

  ## Example

  ```yaml
  - kind: module_completed
    target: 1
  - kind: assessment_passed
    target: module-1-exam
  - kind: policy_acknowledged
    target: usage-policy
  - kind: attendance
    target: team-session
  - kind: qualification_held
    target: assistant-basics
  ```

  Each requirement is valid on its own. The block is the value of
  `requirements` in a qualification; a real qualification lists only the
  requirements that it needs. The validator checks across files that module 1,
  the exam `module-1-exam`, the format `team-session` and the qualification
  `assistant-basics` exist.

  ## Checks

  Errors of the schema:

    * "missing field `kind`" and "missing field `target`".
    * "`kind` must be one of `module_completed`, `assessment_passed`,
      `policy_acknowledged`, `attendance`, `qualification_held`".
    * "the `target` of a `module_completed` requirement must be a module
      number" for a string, a float or an integer below 1.
    * "`target` must be at most 2147483647".
    * "the `target` of a `attendance` requirement must be a string in the key
      format", likewise for the other kinds with a key target.
    * "`target` must have at most 255 characters".
    * "unknown field `x`" for a key that the table does not list.

  Errors of the validator, which runs after the schema stage reports no error.
  Each error sits at the `target` of the requirement:

    * "unknown module `3` in `target`".
    * "unknown assessment `x` in `target`" and "the assessment `x` in `target`
      is no exam".
    * "unknown format `x` in `target`" and "the format `x` in `target` has
      `attendance_counts: false`".
    * "unknown qualification `x` in `target`".
    * "the `qualification_held` requirements of `a` and `b` form a cycle".

  The duplicate check, "duplicate requirement `attendance` `team-session`",
  belongs to the qualification and sits at the index of the second requirement.

  ## See also

  [Content packs](content-packs.md), section "`qualifications.yaml`", and the
  neighbor modules `Espalier.Catalog.Pack.Schema.Qualification` (the owner of
  the list), `Espalier.Catalog.Pack.Schema.Format` (the targets of
  `attendance`) and `Espalier.Catalog.Pack.Validator` (the checks of the
  targets).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2, get_field: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum,
      values: [
        :module_completed,
        :assessment_passed,
        :policy_acknowledged,
        :attendance,
        :qualification_held
      ]

    field :target, :any, virtual: true
  end

  @typedoc "A cast requirement of a qualification."
  @type t :: %__MODULE__{}

  @doc """
  Casts a requirement of a qualification and returns the changeset.

  The errors carry the path of the offending value, which
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` returns.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(requirement, attrs) do
    requirement
    |> Cast.cast(attrs, required: [:kind, :target])
    |> validate_target()
  end

  defp validate_target(changeset) do
    case {get_field(changeset, :kind), get_change(changeset, :target)} do
      {nil, _target} ->
        changeset

      {_kind, nil} ->
        changeset

      {:module_completed, number} when is_integer(number) and number > 0 ->
        if number <= Cast.max_integer(),
          do: changeset,
          else: Cast.add(changeset, :target, "`target` must be at most #{Cast.max_integer()}")

      {:module_completed, _target} ->
        Cast.add(
          changeset,
          :target,
          "the `target` of a `module_completed` requirement must be a module number"
        )

      {kind, target} ->
        key_target(changeset, kind, target)
    end
  end

  # The target lands in `requirements.target_key`, a varchar(255) column.
  defp key_target(changeset, kind, target) do
    cond do
      not Cast.key?(target) ->
        Cast.add(
          changeset,
          :target,
          "the `target` of a `#{kind}` requirement must be a string in the key format"
        )

      not Cast.fits_column?(target) ->
        Cast.add(changeset, :target, "`target` must have at most #{Cast.max_length()} characters")

      true ->
        changeset
    end
  end
end
