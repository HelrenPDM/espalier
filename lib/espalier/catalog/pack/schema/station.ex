defmodule Espalier.Catalog.Pack.Schema.Station do
  @moduledoc """
  An entry of `stations.yaml`: one step of the learner journey of the program.

  `stations.yaml` sits in the pack directory and holds a list of entries. The
  order of the file is the order of the journey. The file is optional. A
  station of kind `module` points to a module of the pack by its number, and
  the stations `self_assessment` and `feedback` depend on `segments.yaml` and
  `feedback.yaml`, as the section "Checks" describes.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `kind` | one of `self_assessment`, `overview`, `module`, `credential`, `companion_formats`, `feedback` | yes | Selects the station type and the `config` that it needs. |
  | `title` | string | yes | At most 255 characters. |
  | `module` | integer | for kind `module` | The module number, from 1 to 2147483647. Allowed on stations of kind `module` only. The number must belong to a module of the pack (checked across files). |
  | `config` | mapping | by kind | Strings, integers, booleans, `null`, lists and mappings with string keys, so that the value survives the `jsonb` column of the payload unchanged. No float, no integer beyond 9,007,199,254,740,991 in either direction, no NUL character. |

  ## Config by kind

  | Kind | `config` |
  |---|---|
  | `self_assessment` | `question` (string, not empty) is required: the question above the segments. |
  | `overview`, `credential`, `companion_formats` | `intro` (string, not empty) is required: the text of the station. |
  | `module` | No key is required. `config: {}` is valid, and so is leaving `config` out. |
  | `feedback` | `intro` and `questions` are not allowed. Both come from `feedback.yaml`. |

  The schema checks no further key of `config`.

  ## Example

  ```yaml
  - kind: self_assessment
    title: Where you start
    config:
      question: How do you use a writing assistant at work today?
  - kind: overview
    title: Overview
    config:
      intro: This program shows how to use a writing assistant safely.
  - kind: module
    title: Working with a writing assistant
    module: 1
  - kind: credential
    title: Your credential
    config:
      intro: Complete the module and pass its exam to receive the credential.
  - kind: feedback
    title: Your feedback
  ```

  Each entry is valid on its own. The validator checks across files that
  module 1 exists, that `segments.yaml` has entries because the pack has a
  `self_assessment` station, and that `feedback.yaml` exists because the pack
  has a `feedback` station.

  ## Checks

  Errors of the schema:

    * "missing field `kind`" and "missing field `title`".
    * "`kind` must be one of `self_assessment`, `overview`, `module`,
      `credential`, `companion_formats`, `feedback`".
    * "`title` must have at most 255 characters".
    * "a station of kind `module` needs `module`, the module number" and
      "`module` is allowed on stations of kind `module` only".
    * "`module` must be at least 1".
    * "a `self_assessment` station needs the text `question` in `config`" and
      the same for `intro` on the stations `overview`, `credential` and
      `companion_formats`.
    * "`intro` in `config` must not be empty", likewise for `question`.
    * "the `feedback` station takes `intro` from `feedback.yaml`", likewise for
      `questions`.
    * "`config` holds a number with a fraction or an exponent; use an integer
      or a quoted string", and the messages for an integer beyond the bounds or
      a NUL character.
    * "unknown field `x`" for a key that the table does not list.

  Errors of the validator, which runs after the schema stage reports no error:

    * "unknown module `3` in `module`" when no module has that number.
    * "the pack needs a `self_assessment` station, because `segments.yaml` has
      entries" and "a `self_assessment` station needs entries in
      `segments.yaml`".
    * "the pack needs a `feedback` station, because `feedback.yaml` exists" and
      "a `feedback` station needs `feedback.yaml`".
    * "the pack has one `self_assessment` station only" on a second station of
      that kind, likewise for `feedback`.

  ## See also

  [Content packs](content-packs.md), section "`stations.yaml`", and the
  neighbor modules `Espalier.Catalog.Pack.Schema.Segment` (the segments that
  the `self_assessment` station presents), `Espalier.Catalog.Pack.Schema.Feedback`
  (the content of the `feedback` station), `Espalier.Catalog.Pack.Schema.PackModule`
  (the modules that stations of kind `module` point to) and
  `Espalier.Catalog.Pack.Validator` (the cross-file checks).
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

  @typedoc "A cast entry of `stations.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts an entry of `stations.yaml` and returns the changeset.

  The errors carry the path of the offending value, which
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` returns.
  """
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
