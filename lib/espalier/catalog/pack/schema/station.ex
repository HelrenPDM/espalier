defmodule Espalier.Catalog.Pack.Schema.Station do
  @moduledoc """
  An entry of `stations.yaml`: `kind`, `title`, `module` (the module number,
  for kind `module` only and required there) and an optional `config` that
  holds strings, integers, booleans, `null`, lists and maps with string keys
  only (`Espalier.Catalog.Pack.Schema.Cast.validate_json/2`), so that it
  survives the `jsonb` column of the payload unchanged.

  The `self_assessment` station holds `question` in `config`, and the
  `overview`, `credential` and `companion_formats` stations hold `intro`.
  The `feedback` station receives `intro` and `questions` from
  `feedback.yaml`, so its own `config` names neither.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2, get_field: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @intro_kinds [:overview, :credential, :companion_formats]

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum,
      values: [:self_assessment, :overview, :module, :credential, :companion_formats, :feedback]

    field :title, :string
    field :module, :integer
    field :config, :map
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `stations.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(station, attrs) do
    station
    |> Cast.cast(attrs, required: [:kind, :title])
    |> Cast.validate_max_length(:title)
    |> Cast.validate_json(:config)
    |> validate_module()
    |> validate_config()
  end

  defp validate_module(changeset) do
    case {get_field(changeset, :kind), get_change(changeset, :module)} do
      {:module, nil} ->
        if Cast.errored?(changeset, :module),
          do: changeset,
          else:
            Cast.add(
              changeset,
              :module,
              "a station of kind `module` needs `module`, the module number"
            )

      {:module, _number} ->
        Cast.validate_min(changeset, :module, 1)

      {_kind, nil} ->
        changeset

      {_kind, _number} ->
        Cast.add(changeset, :module, "`module` is allowed on stations of kind `module` only")
    end
  end

  defp validate_config(changeset) do
    config = get_change(changeset, :config) || %{}

    if Cast.errored?(changeset, :config),
      do: changeset,
      else: validate_config(changeset, get_field(changeset, :kind), config)
  end

  defp validate_config(changeset, :self_assessment, config),
    do: require_text(changeset, config, :self_assessment, "question")

  defp validate_config(changeset, kind, config) when kind in @intro_kinds,
    do: require_text(changeset, config, kind, "intro")

  defp validate_config(changeset, :feedback, config) do
    config
    |> Map.keys()
    |> Enum.filter(&(&1 in ["intro", "questions"]))
    |> Enum.sort()
    |> Enum.reduce(changeset, fn key, changeset ->
      Cast.add(
        changeset,
        :config,
        [key],
        "the `feedback` station takes `#{key}` from `feedback.yaml`"
      )
    end)
  end

  defp validate_config(changeset, _kind, _config), do: changeset

  defp require_text(changeset, config, kind, key) do
    case Map.get(config, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: Cast.add(changeset, :config, [key], "`#{key}` in `config` must not be empty"),
          else: changeset

      _ ->
        Cast.add(
          changeset,
          :config,
          [key],
          "a `#{kind}` station needs the text `#{key}` in `config`"
        )
    end
  end
end
