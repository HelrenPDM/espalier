defmodule Espalier.Catalog.Pack.Schema.Item do
  @moduledoc """
  An entry of `modules/<directory>/items.yaml`, a practice or exam item:
  `key`, `kind`, `lesson` (a lesson key of the module; required for an item
  that no assessment lists, absent for an exam item), `stem`, `core`,
  `phase`, `provenance`, and the optional lists `objectives` (objective keys
  of the pack), `rules` (rule numbers of the module), `reveals` (lesson keys
  of the module) and `cite` (`source-key#locator`).

  Kinds carry what they need:

  | Kind | Needs |
  |---|---|
  | `single_choice` | `options`: at least two, exactly one correct |
  | `multiple_choice` | `options`: at least two, at least one correct |
  | `poll` | `options`: at least two, none correct |
  | `slot_builder` | `config` (`Espalier.Catalog.Pack.Schema.SlotBuilderConfig`) |
  | `classification` | `config` (`Espalier.Catalog.Pack.Schema.ClassificationConfig`) |
  | `checklist_drill` | `config` (`Espalier.Catalog.Pack.Schema.ChecklistDrillConfig`) |

  A choice kind or a poll takes no `config`, and the other kinds take no
  `options`. After the cast, `config` holds the cast config struct.
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

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `items.yaml`."
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
