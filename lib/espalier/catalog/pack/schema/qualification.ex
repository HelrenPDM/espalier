defmodule Espalier.Catalog.Pack.Schema.Qualification do
  @moduledoc """
  An entry of `qualifications.yaml`: `code`, `title`, `audience`, `unlocks`,
  `add_on`, `validity_kind`, `validity_months`, `refresher_mode`, `phases`
  and at least one requirement in `requirements`
  (`Espalier.Catalog.Pack.Schema.Requirement`).

  `validity_kind: months` needs `validity_months` above 0, and only that kind
  takes `validity_months`. `months` and `event` need a `refresher_mode`, and
  `none` takes none. A requirement appears once per qualification.
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
    embeds_many :requirements, Requirement
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `qualifications.yaml`."
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
