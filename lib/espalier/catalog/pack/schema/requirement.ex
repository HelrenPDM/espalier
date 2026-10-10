defmodule Espalier.Catalog.Pack.Schema.Requirement do
  @moduledoc """
  A requirement of a qualification: `kind` and `target`. The target is the
  module number (an integer from 1 to 2147483647) for `module_completed`,
  and a string in the key format of at most 255 characters for the other
  kinds: the assessment key for `assessment_passed`, the policy key for
  `policy_acknowledged`, the format key for `attendance` and the
  qualification code for `qualification_held`.
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

  @type t :: %__MODULE__{}

  @doc "Casts a requirement of a qualification."
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
