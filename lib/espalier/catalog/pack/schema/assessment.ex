defmodule Espalier.Catalog.Pack.Schema.Assessment do
  @moduledoc """
  An entry of `assessment.yaml`: a practice assessment or an exam of a module, with the items it asks in order.

  `modules/<directory>/assessment.yaml` holds a list of entries. The file is
  optional; a module without it has no assessment, and then every item of the
  module must name a `lesson`. A qualification refers to an exam by its `key`
  in a requirement of kind `assessment_passed` (`qualifications.yaml`). The
  items are entries of `items.yaml` of the same module; the assessment lists
  only their keys.

  An item that an assessment of kind `exam` lists is an exam item, and every
  other item is a practice item. An exam item names no `lesson`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | string in the key format | yes | `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the pack. |
  | `title` | string | yes | Not empty, at most 255 characters. |
  | `kind` | one of `practice`, `exam` | yes | `exam` is the only kind that a qualification can require. |
  | `counts_for_credential` | boolean | yes | `true` or `false`. With `true`, every item of the assessment must name at least one objective. |
  | `max_wrong` | integer | yes | At least 0, at most 2147483647. The number of wrong answers that a passed attempt may hold. For an exam, at most the number of its items minus one. |
  | `core_required` | boolean | yes | `true` or `false`. With `true` on an exam, at least one item of the exam must be a core item (`core: true` in `items.yaml`). The validator does not check the field on a practice assessment. |
  | `items` | list of string in the key format | yes | At least one entry. Item keys of the same module, in the order of the attempt, no key twice. |

  ## Example

  ```yaml
  - key: module-1-practice
    title: Practice for module 1
    kind: practice
    counts_for_credential: false
    max_wrong: 2
    core_required: false
    items:
      - m1-how-models-write
      - m1-fluent-figure
      - m1-why-answers-vary
  - key: module-1-exam
    title: Exam of module 1
    kind: exam
    counts_for_credential: true
    max_wrong: 1
    core_required: true
    items:
      - m1-exam-next-word
      - m1-exam-varying-answers
      - m1-exam-check-claims
  ```

  The schema checks the form of the item keys. The validator resolves them
  against `items.yaml` of the module, and the exam rules below use the fields
  of those items, so the block is valid for this schema alone and valid in a
  pack only when the items exist and fit.

  ## Checks

  The schema reports:

    * `` `assessment.yaml` must hold a list of entries `` when the file holds no list;
    * `` missing field `kind` ``, and the same for every other required field;
    * `` `kind` must be one of `practice`, `exam` ``;
    * `` `counts_for_credential` must be `true` or `false` ``, and the same for `core_required`;
    * `` `max_wrong` must be at least 0 ``;
    * `` `max_wrong` of an exam with 3 items must be between 0 and 2 `` when the kind is `exam` and the value exceeds the number of items minus one;
    * `` `items` needs at least one item ``, and `` duplicate entry `x` in `items` ``;
    * `` `items` value `M1_Exam` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``, and `` `title` must have at most 255 characters ``.

  The checks across files report:

    * `` duplicate assessment key `x`, first used in `modules/<directory>/assessment.yaml` at line 1 ``;
    * `` unknown item `x` of this module in `items` ``;
    * `` the item `x` of the exam `y` must not name a `lesson` ``, at the item in `items.yaml`;
    * `` the item `x` names no `lesson`, and no assessment lists it ``, for an item that neither names a lesson nor appears in an assessment;
    * `` the exam `x` has `core_required: true` and no core item ``;
    * `` unknown assessment `x` in `target` `` and `` the assessment `x` in `target` is no exam ``, at a requirement of kind `assessment_passed` in `qualifications.yaml`.

  The alignment check (check 2 of `Espalier.Catalog.Alignment.check/1`)
  reports an item of an assessment with `counts_for_credential: true` that
  names no objective in `objectives` of `items.yaml`. The finding is an error
  with `alignment: strict` (the default) and a warning with `alignment: warn`.
  An item that an assessment lists also counts as evidence for the objectives
  that it names, whatever its kind.

  ## See also

    * [Content packs](content-packs.md), the section on `assessment.yaml`
    * `Espalier.Catalog.Pack.Schema.Item`, the items that `items` names
    * `Espalier.Catalog.Pack.Schema.Qualification`, whose requirements name exams by key
    * `Espalier.Catalog.Pack.Schema.Objective`, the objectives that the items serve
    * `Espalier.Catalog.Pack.Validator`, the checks across files
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :title, :string
    field :kind, Ecto.Enum, values: [:practice, :exam]
    field :counts_for_credential, :boolean
    field :max_wrong, :integer
    field :core_required, :boolean
    field :items, {:array, :string}
  end

  @typedoc "The cast contents of an entry of `assessment.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `assessment.yaml`.

  Returns a changeset that is valid when the entry follows the rules of the
  moduledoc, including the bound of `max_wrong` for an exam.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(assessment, attrs) do
    assessment
    |> Cast.cast(attrs,
      required: [:key, :title, :kind, :counts_for_credential, :max_wrong, :core_required, :items]
    )
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_min(:max_wrong, 0)
    |> Cast.validate_length(:items, 1, "`items` needs at least one item")
    |> Cast.validate_keys(:items)
    |> Cast.validate_unique(:items)
    |> validate_exam_max_wrong()
  end

  defp validate_exam_max_wrong(changeset) do
    items = changeset |> get_field(:items) |> List.wrap()
    max_wrong = get_field(changeset, :max_wrong)

    if get_field(changeset, :kind) == :exam and items != [] and is_integer(max_wrong) and
         max_wrong > length(items) - 1,
       do:
         Cast.add(
           changeset,
           :max_wrong,
           "`max_wrong` of an exam with #{length(items)} items must be between 0 and #{length(items) - 1}"
         ),
       else: changeset
  end
end
