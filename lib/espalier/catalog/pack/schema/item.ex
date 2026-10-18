defmodule Espalier.Catalog.Pack.Schema.Item do
  @moduledoc """
  An entry of `items.yaml`: a practice item or an exam item of a module.

  `modules/<directory>/items.yaml` holds one list of items. The file is
  optional; a module without it has no items. The `key` of an item is unique
  in the whole pack. Assessments list items by `key` in their `items`
  (`Espalier.Catalog.Pack.Schema.Assessment`), and an item of an exam is an
  exam item. Every other item is a practice item. The player shows a practice item
  that names a `lesson` in the section of that lesson, and a practice item
  without a `lesson` (an assessment of kind `practice` lists it) in the
  section "More practice".

  The `kind` of an item selects what the item carries. The kinds
  `single_choice`, `multiple_choice` and `poll` carry `options`, and the other
  three kinds carry `config`:

  | Kind | Carries | Rules | Correct answer |
  |---|---|---|---|
  | `single_choice` | `options` | At least two options, exactly one with `correct: true` | the one correct option |
  | `multiple_choice` | `options` | At least two options, at least one with `correct: true` | exactly the set of correct options |
  | `poll` | `options` | At least two options, none with `correct: true` | none; a poll is never correct or wrong |
  | `slot_builder` | `config` | `Espalier.Catalog.Pack.Schema.SlotBuilderConfig` | a correct option in every slot |
  | `classification` | `config` | `Espalier.Catalog.Pack.Schema.ClassificationConfig` | every case in its expected category |
  | `checklist_drill` | `config` | `Espalier.Catalog.Pack.Schema.ChecklistDrillConfig` | every required check set and initials of 2 to 5 characters |

  An option has the shape of `Espalier.Catalog.Pack.Schema.Option`. The kinds
  with `options` take no `config`, and the kinds with `config` take no
  `options`.
  After the cast, `config` holds the cast config struct of the kind.
  `Espalier.Learning.Evaluator` evaluates answers to items, and the column
  "Correct answer" restates its rules.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | Matches `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the pack. |
  | `kind` | one of `single_choice`, `multiple_choice`, `slot_builder`, `classification`, `checklist_drill`, `poll` | yes | Selects `options` or `config`, as the table above shows. |
  | `lesson` | key | for a practice item that no assessment lists | A lesson key of the same module. An item that an exam lists must not name a lesson. |
  | `stem` | string | yes | The question or task. A non-empty string. |
  | `core` | boolean | yes | `true` or `false`. A wrong answer to a core item fails an exam attempt. An exam with `core_required: true` lists at least one core item. |
  | `phase` | one of `orient`, `understand`, `apply`, `anchor`, `update` | yes | The phase of the five-phase arc. |
  | `provenance` | one of `invented`, `sourced`, `vendor_statement`, `assumption`, `placeholder` | yes | The origin of the item, shown as a badge. |
  | `objectives` | list of key | no | Objective keys of the pack, each in the key format and listed once. An objective may belong to another module. |
  | `rules` | list of integer | no | Rule numbers of the same module, each listed once and at most 2147483647. |
  | `reveals` | list of key | no | Lesson keys of the same module, each listed once. The explanations of these lessons open after a wrong answer. |
  | `cite` | list of string | no | Entries of the form `source-key#locator`, each listed once. The locator has at most 255 characters, and the source key is a `key` of `sources.yaml`. |
  | `options` | list of mappings | for `single_choice`, `multiple_choice` and `poll` | Entries of `Espalier.Catalog.Pack.Schema.Option` with unique keys. Not allowed for the other kinds. |
  | `config` | mapping | for `slot_builder`, `classification` and `checklist_drill` | The configuration of the kind. Not allowed for the choice kinds and the poll. |

  The validator checks across files that `lesson`, `rules`, `reveals`,
  `objectives` and `cite` resolve to a lesson and rules of the same module,
  to an objective of the pack and to a source of the pack. It also checks
  that an item either names a `lesson` or is listed by an assessment, and
  that an item of an exam names no `lesson`.

  ## Example

  Two practice items of a module: a single-choice item with a citation and a
  poll. The lesson, the rule, the objective and the source are defined in
  other files of the pack, and the validator checks those references there.

  ```yaml
  - key: m1-likely-words
    kind: single_choice
    lesson: 01-how-it-writes
    stem: How does a writing assistant produce its answer?
    core: false
    phase: understand
    provenance: sourced
    objectives: [m1-subject-likely-words]
    rules: [1]
    reveals: [01-how-it-writes]
    cite: ["assistant-manual#Chapter 2"]
    options:
      - key: likely-words
        label: It continues the text with words that are likely to follow.
        correct: true
        feedback: Right. The assistant continues text from learned probabilities.
      - key: checked-facts
        label: It looks up the answer in a list of checked facts.
        correct: false
        feedback: The assistant holds no list of checked facts.
  - key: m1-first-task-poll
    kind: poll
    lesson: 01-how-it-writes
    stem: For which task would you use a writing assistant first?
    core: false
    phase: orient
    provenance: invented
    options:
      - key: notices
        label: Short notices
        correct: false
        feedback: Thank you for your answer.
      - key: summaries
        label: Summaries
        correct: false
        feedback: Thank you for your answer.
  ```

  The schema requires `feedback` on the options of a poll, but the evaluation
  of a poll returns no option feedback, so no learner sees that text.

  An exam item names no `lesson`, because an exam lists it in the `items` of
  its assessment. This multiple-choice item is a core item:

  ```yaml
  - key: m1-exam-varying-drafts
    kind: multiple_choice
    stem: You send the same prompt twice and receive two drafts. Which statements are true?
    core: true
    phase: anchor
    provenance: invented
    objectives: [m1-subject-likely-words]
    options:
      - key: both-fluent
        label: Both drafts can read well and still differ in their facts.
        correct: true
        feedback: Right. Fluent wording says nothing about the facts.
      - key: expected
        label: Different drafts are expected, because the assistant chooses among likely words.
        correct: true
        feedback: Right. The choice among likely words varies.
      - key: fault
        label: One of the drafts is the result of a technical fault.
        correct: false
        feedback: The variation is part of how the assistant works.
  ```

  A kind with `config` carries the mapping of its config module in place of
  `options`. This checklist drill shows the position of `config`; the config
  modules hold the examples of the other two kinds:

  ```yaml
  - key: m1-release-drill
    kind: checklist_drill
    lesson: 02-prompts-and-checks
    stem: Run the release checks on your draft notice and confirm them with your initials.
    core: false
    phase: apply
    provenance: invented
    rules: [2]
    config:
      checks:
        - key: facts-checked
          label: Every name, number and date in the draft is checked against a source.
          required: true
        - key: second-reader
          label: A colleague has read the draft.
          required: false
  ```

  ## Checks

  The cast reports these errors of an entry:

    * `` unknown field `x` ``, `` missing field `stem` `` and
      `` `stem` has no value `` for a required field with a `null` value;
    * `` `kind` must be one of `single_choice`, `multiple_choice`, `slot_builder`, `classification`, `checklist_drill`, `poll` ``,
      and the same form for `phase` and `provenance`;
    * `` `key` value `X` does not match the key format `^[a-z0-9][a-z0-9-]*$` ``,
      with the name of the failing field in place of `key`: `lesson`,
      `objectives` or `reveals` for the entries of those lists;
    * `` duplicate entry `x` in `objectives` `` (also for `rules`, `reveals`
      and `cite`) and `` duplicate key `x` in `options` ``;
    * `` `cite` entry `x` does not have the form `source-key#locator` ``;
    * `` a `single_choice` item needs at least two options ``;
    * `` a `single_choice` item has exactly one correct option, found 2 ``;
    * `` a `multiple_choice` item has at least one correct option ``;
    * `` a `poll` item has no correct option ``;
    * `` a `slot_builder` item needs `config` `` (also for `classification` and
      `checklist_drill`);
    * `` `config` is not allowed for kind `poll` `` and
      `` `options` is not allowed for kind `slot_builder` ``, with the kind
      of the item in the message.

  The errors of `config` carry the path below `config`, and the errors of an
  option carry the path below `options`. The validator adds these errors
  across files:

    * `` unknown lesson `x` of this module in `lesson` `` (and the same form
      for `reveals`), `` unknown rule `3` of this module in `rules` `` and
      `` unknown objective `x` in `objectives` ``;
    * `` unknown source `x` in `cite` ``;
    * `` duplicate item key `x`, first used in `modules/01-basics/items.yaml` at line 4 ``;
    * `` the item `x` names no `lesson`, and no assessment lists it `` and
      `` the item `x` of the exam `y` must not name a `lesson` ``;
    * `` the exam `y` has `core_required: true` and no core item ``.

  The alignment checks add findings on items. An item that an assessment with
  `counts_for_credential: true` lists names at least one objective, and the
  `kind` of an item decides whether it is evidence of an objective and of
  which depth (`Espalier.Catalog.Alignment`).

  ## See also

  [Content packs](content-packs.md), section "Item kinds", describes the
  kinds and the cross-file checks. The modules
  `Espalier.Catalog.Pack.Schema.Option`,
  `Espalier.Catalog.Pack.Schema.SlotBuilderConfig`,
  `Espalier.Catalog.Pack.Schema.ClassificationConfig` and
  `Espalier.Catalog.Pack.Schema.ChecklistDrillConfig` define the parts of an
  item. `Espalier.Catalog.Pack.Schema.Assessment` lists items by key.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2, get_field: 2]

  alias Espalier.Catalog.Pack.Schema.{
    Cast,
    ChecklistDrillConfig,
    ClassificationConfig,
    Option,
    SlotBuilderConfig
  }

  @phases [:orient, :understand, :apply, :anchor, :update]
  @option_kinds [:single_choice, :multiple_choice, :poll]
  @configs %{
    slot_builder: SlotBuilderConfig,
    classification: ClassificationConfig,
    checklist_drill: ChecklistDrillConfig
  }

  @primary_key false
  embedded_schema do
    field :key, :string

    field :kind, Ecto.Enum,
      values: [
        :single_choice,
        :multiple_choice,
        :slot_builder,
        :classification,
        :checklist_drill,
        :poll
      ]

    field :lesson, :string
    field :stem, :string
    field :core, :boolean
    field :phase, Ecto.Enum, values: @phases

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :objectives, {:array, :string}
    field :rules, {:array, :integer}
    field :reveals, {:array, :string}
    field :cite, {:array, :string}
    field :config, :map
    embeds_many :options, Option
  end

  @typedoc "An item, as cast from an entry of `items.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an entry of `items.yaml` and checks `options` and `config` against its
  `kind`.

  Returns an `Ecto.Changeset`. When it is valid, `config` holds the cast
  config struct of the kind.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> Cast.cast(attrs, required: [:key, :kind, :stem, :core, :phase, :provenance])
    |> Cast.validate_key(:key)
    |> Cast.validate_key(:lesson)
    |> Cast.validate_keys(:objectives)
    |> Cast.validate_unique(:objectives)
    |> Cast.validate_unique(:rules)
    |> Cast.validate_keys(:reveals)
    |> Cast.validate_unique(:reveals)
    |> Cast.validate_cite(:cite)
    |> Cast.validate_unique(:cite)
    |> Cast.validate_unique_by(:options, :key)
    |> validate_kind()
  end

  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      nil ->
        changeset

      kind when kind in @option_kinds ->
        changeset |> forbid(:config, kind) |> validate_options(kind)

      kind ->
        changeset |> forbid(:options, kind) |> validate_config(kind)
    end
  end

  defp forbid(changeset, field, kind) do
    if present?(changeset, field),
      do: Cast.add(changeset, field, "`#{field}` is not allowed for kind `#{kind}`"),
      else: changeset
  end

  defp validate_options(changeset, kind) do
    options = changeset |> get_field(:options) |> List.wrap()
    correct = Enum.count(options, &(&1.correct == true))
    message = option_error(kind, length(options), correct)

    cond do
      is_nil(message) or Cast.errored?(changeset, :options) -> changeset
      present?(changeset, :options) -> Cast.add(changeset, :options, message)
      true -> Cast.add_entry_error(changeset, message)
    end
  end

  defp option_error(kind, count, _correct) when count < 2,
    do: "a `#{kind}` item needs at least two options"

  defp option_error(:single_choice, _count, 1), do: nil

  defp option_error(:single_choice, _count, correct),
    do: "a `single_choice` item has exactly one correct option, found #{correct}"

  defp option_error(:multiple_choice, _count, 0),
    do: "a `multiple_choice` item has at least one correct option"

  defp option_error(:poll, _count, correct) when correct > 0,
    do: "a `poll` item has no correct option"

  defp option_error(_kind, _count, _correct), do: nil

  defp validate_config(changeset, kind) do
    cond do
      Cast.errored?(changeset, :config) ->
        changeset

      is_nil(get_change(changeset, :config)) ->
        Cast.add_entry_error(changeset, "a `#{kind}` item needs `config`")

      true ->
        Cast.cast_nested(changeset, :config, Map.fetch!(@configs, kind))
    end
  end

  defp present?(changeset, field),
    do: Map.has_key?(changeset.params || %{}, Atom.to_string(field))
end
