defmodule Espalier.Catalog.Pack.Schema.Qualification do
  @moduledoc """
  An entry of `qualifications.yaml`: a qualification and the requirements that issue its credential.

  `qualifications.yaml` sits in the pack directory and holds a list of
  entries. The file is optional. The `code` of an entry is the target of the
  `qualification_held` requirements of other entries. A qualification lists
  its requirements in `requirements`, and each requirement is described by
  `Espalier.Catalog.Pack.Schema.Requirement`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `code` | key | yes | `^[a-z0-9][a-z0-9-]*$`, at most 255 characters, unique in the file. |
  | `title` | string | yes | At most 255 characters. |
  | `audience` | string | yes | The people that the qualification addresses. No length limit is checked. |
  | `unlocks` | list of string | no | The tasks that a holder may do. Each entry has at most 255 characters, and no entry appears twice. The normalized pack holds an empty list when the field is absent. |
  | `add_on` | boolean | yes | `true` or `false`. |
  | `validity_kind` | one of `none`, `months`, `event` | yes | Decides which of `validity_months` and `refresher_mode` apply, see below. |
  | `validity_months` | integer | with `validity_kind: months` | Above 0 and at most 2147483647. Allowed with `validity_kind: months` only. |
  | `refresher_mode` | one of `update_unit`, `full_run`, `test_only` | with `validity_kind` `months` or `event` | Not allowed with `validity_kind: none`. The value `update_unit` needs a module with `refresher_unit: true` in the pack (checked across files). |
  | `phases` | list of one of `orient`, `understand`, `apply`, `anchor`, `update` | no | No entry appears twice. |
  | `position` | integer | no | At least 1. Orders the qualifications for display and has no other meaning, see "Order". |
  | `requirements` | list of mappings | yes | At least one entry. Each entry has `kind` and `target`. The same `kind` with the same `target` appears once per qualification. |

  ## Order

  `position` is set on every entry of the file or on none, and no value
  appears twice. With positions, the qualifications follow `position`;
  without positions, they follow the order of the file. The normalized pack
  keeps the order and holds no `position`.

  ## Example

  ```yaml
  - code: assistant-basics
    title: Writing assistant basics
    audience: Everyone who drafts texts with a writing assistant.
    unlocks:
      - Draft internal texts with an approved writing assistant
    add_on: false
    validity_kind: months
    validity_months: 12
    refresher_mode: update_unit
    phases: [understand, apply, anchor]
    position: 1
    requirements:
      - kind: module_completed
        target: 1
      - kind: assessment_passed
        target: module-1-exam
      - kind: policy_acknowledged
        target: usage-policy
  - code: team-practice
    title: Writing assistant in the team
    audience: Holders of the credential Writing assistant basics who share texts with a team.
    unlocks:
      - Agree with a team how the use of a writing assistant is marked in shared texts
    add_on: true
    validity_kind: none
    phases: [anchor]
    position: 2
    requirements:
      - kind: qualification_held
        target: assistant-basics
      - kind: attendance
        target: team-session
  ```

  Each entry is valid on its own. The validator checks across files that
  module 1 exists, that `module-1-exam` is an assessment of kind `exam`, that
  the format `team-session` exists with `attendance_counts: true`, and that
  some module has `refresher_unit: true`, because the first entry sets
  `refresher_mode: update_unit`.

  ## Checks

  Errors of the schema:

    * "missing field `code`", likewise for `title`, `audience`, `add_on`,
      `validity_kind` and `requirements`.
    * "`code` value `x` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "`title` must have at most 255 characters" and "entries of `unlocks` must
      have at most 255 characters".
    * "duplicate entry `x` in `unlocks`", likewise for `phases`.
    * "`validity_kind` must be one of `none`, `months`, `event`", and likewise
      for `refresher_mode` and the entries of `phases`.
    * "`validity_kind: months` needs `validity_months` above 0".
    * "`validity_months` is allowed with `validity_kind: months` only".
    * "`validity_kind: months` needs a `refresher_mode`", likewise for `event`.
    * "`refresher_mode` is allowed with `validity_kind` `months` or `event`
      only".
    * "`requirements` needs at least one requirement".
    * "duplicate requirement `module_completed` `1`".
    * "`position` must be at least 1".
    * "unknown field `x`" for a key that the table does not list.

  Errors of the validator, which runs after the schema stage reports no error:

    * "duplicate qualification code `x`, first used in `qualifications.yaml` at
      line N".
    * "`position` must be set on every qualification or on none" and "duplicate
      qualification position `1`, first used in `qualifications.yaml` at line
      N".
    * "`refresher_mode: update_unit` needs a module with `refresher_unit: true`".
    * The errors of the requirement targets, which
      `Espalier.Catalog.Pack.Schema.Requirement` lists.

  ## See also

  [Content packs](content-packs.md), section "`qualifications.yaml`", and the
  neighbor modules `Espalier.Catalog.Pack.Schema.Requirement` (the entries of
  `requirements`), `Espalier.Catalog.Pack.Schema.Format` (the formats that
  `attendance` requirements point to), `Espalier.Catalog.Pack.Schema.PackModule`
  (`refresher_unit`) and `Espalier.Catalog.Pack.Validator` (the cross-file
  checks).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{Cast, Requirement}

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :code, :string
    field :title, :string
    field :audience, :string
    field :unlocks, {:array, :string}
    field :add_on, :boolean
    field :validity_kind, Ecto.Enum, values: [:none, :months, :event]
    field :validity_months, :integer
    field :refresher_mode, Ecto.Enum, values: [:update_unit, :full_run, :test_only]
    field :phases, {:array, Ecto.Enum}, values: @phases
    field :position, :integer
    embeds_many :requirements, Requirement
  end

  @typedoc "A cast entry of `qualifications.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an entry of `qualifications.yaml` and returns the changeset.

  The errors carry the path of the offending value, which
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` returns.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(qualification, attrs) do
    qualification
    |> Cast.cast(attrs,
      required: [:code, :title, :audience, :add_on, :validity_kind, :requirements]
    )
    |> Cast.validate_key(:code)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_max_length(:unlocks)
    |> Cast.validate_unique(:unlocks)
    |> Cast.validate_unique(:phases)
    |> Cast.validate_length(:requirements, 1, "`requirements` needs at least one requirement")
    |> Cast.validate_min(:position, 1)
    |> validate_months()
    |> validate_refresher()
    |> validate_unique_requirements()
  end

  defp validate_months(changeset) do
    kind = get_field(changeset, :validity_kind)
    months = get_field(changeset, :validity_months)

    cond do
      Cast.errored?(changeset, :validity_months) or is_nil(kind) ->
        changeset

      kind == :months and (is_nil(months) or months < 1) ->
        Cast.add(
          changeset,
          :validity_months,
          "`validity_kind: months` needs `validity_months` above 0"
        )

      kind != :months and not is_nil(months) ->
        Cast.add(
          changeset,
          :validity_months,
          "`validity_months` is allowed with `validity_kind: months` only"
        )

      true ->
        changeset
    end
  end

  defp validate_refresher(changeset) do
    kind = get_field(changeset, :validity_kind)
    mode = get_field(changeset, :refresher_mode)

    cond do
      Cast.errored?(changeset, :refresher_mode) or is_nil(kind) ->
        changeset

      kind in [:months, :event] and is_nil(mode) ->
        Cast.add(changeset, :refresher_mode, "`validity_kind: #{kind}` needs a `refresher_mode`")

      kind == :none and not is_nil(mode) ->
        Cast.add(
          changeset,
          :refresher_mode,
          "`refresher_mode` is allowed with `validity_kind` `months` or `event` only"
        )

      true ->
        changeset
    end
  end

  defp validate_unique_requirements(changeset) do
    changeset
    |> get_field(:requirements)
    |> List.wrap()
    |> Enum.with_index()
    # Only a string or an integer can be a valid target; validate_target/1
    # reports every other value already.
    |> Enum.filter(fn {requirement, _index} ->
      not is_nil(requirement.kind) and
        (is_binary(requirement.target) or is_integer(requirement.target))
    end)
    |> Enum.reduce({changeset, MapSet.new()}, fn {requirement, index}, {changeset, seen} ->
      pair = {requirement.kind, requirement.target}

      if MapSet.member?(seen, pair),
        do:
          {Cast.add(
             changeset,
             :requirements,
             [index],
             "duplicate requirement `#{requirement.kind}` `#{requirement.target}`"
           ), seen},
        else: {changeset, MapSet.put(seen, pair)}
    end)
    |> elem(0)
  end
end
