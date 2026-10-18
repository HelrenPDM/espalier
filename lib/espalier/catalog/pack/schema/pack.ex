defmodule Espalier.Catalog.Pack.Schema.Pack do
  @moduledoc """
  The `pack.yaml` file: format version, identity, language, license and alignment mode of a content pack.

  `pack.yaml` sits in the root of the pack directory and holds one mapping. It is the only required file in the root of the pack directory. The pack also needs at least one module directory under `modules/`, with `module.yaml` and at least one lesson file. `key`, `title`, `locale` and `version` are stored on the program (`programs.slug`, `title`, `locale` and `pack_version`), and an import whose `key` names an existing program updates that program when it is published. `license` and `alignment` stay in the payload of the published import. `alignment` decides how `Espalier.Catalog.Alignment` reports its findings.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `schema` | integer | yes | One of the supported format versions, currently `1` (`supported_schemas/0`). A string such as `"1"` and any other number are errors that name the supported versions. |
  | `key` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Becomes `programs.slug`. |
  | `title` | string | yes | At most 255 characters. |
  | `locale` | string | yes | A language tag: a lowercase language subtag of 2 or 3 letters, optionally followed by subtags of 2 to 8 letters or digits, each after a hyphen, such as `en` or `de-DE`. At most 255 characters. |
  | `license` | string | yes | An SPDX license expression such as `CC0-1.0` or `MIT OR Apache-2.0`, whose license and exception ids are on the SPDX License List of `Espalier.Catalog.Pack.Spdx`, without regard to case. A `+` may follow a license id, parentheses group, and references of the forms `LicenseRef-...` and `AdditionRef-...` are accepted without being on the list. The operators `AND`, `OR` and `WITH` are written in capitals. |
  | `version` | string | yes | The version of the pack, at most 255 characters. Becomes `programs.pack_version`. The text is free, but a value that YAML reads as a number, such as `1.0` or `2`, must be quoted to be read as a string, as in `"1.0.0"`. |
  | `alignment` | one of `strict`, `warn` | no | Defaults to `strict`. With `strict`, the findings of checks 1 to 3 of `Espalier.Catalog.Alignment` are errors; with `warn`, they are warnings. The findings of check 4 are warnings in both modes. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  ```yaml
  schema: 1
  key: writing-assistant-basics
  title: Safe use of a writing assistant
  locale: en
  license: CC0-1.0
  version: "1.0.0"
  alignment: strict
  ```

  ## Checks

    * "missing file" for `pack.yaml` when the pack has none, and "`pack.yaml` must hold a map" when the file holds anything else.
    * "missing field `key`" and "`key` has no value" for a required field that is absent or `null`; the same for `schema`, `title`, `locale`, `license` and `version`.
    * "unknown field `name`" for a key that the table does not list.
    * "unsupported schema version `2`; supported versions: `1`". The validator then reports the errors of `pack.yaml` only.
    * "`key` value `Writing` does not match the key format `^[a-z0-9][a-z0-9-]*$`" and "`key` must have at most 255 characters"; the second message also applies to `title`, `locale` and `version`.
    * "`version` must be a string" for an unquoted number such as `1.0`.
    * "`locale` must be a language tag such as `en` or `de-DE`".
    * "`license` must be an SPDX license expression such as `CC0-1.0` or `MIT OR Apache-2.0`, with ids of SPDX License List" followed by the list version.
    * "`alignment` must be one of `strict`, `warn`".

  ## See also

  [Content packs](content-packs.md), section "`pack.yaml`", and [Course YAML](course-yaml.md) for the overview of the files. The neighbor modules are `Espalier.Catalog.Pack.Spdx` (the license grammar), `Espalier.Catalog.Alignment` (the alignment checks), `Espalier.Catalog.Pack.Loader` (reads the file) and `Espalier.Catalog.Pack.Validator` (runs the cast).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2]

  alias Espalier.Catalog.Pack.Schema.Cast
  alias Espalier.Catalog.Pack.Spdx

  @supported_schemas [1]
  @locale_regex ~r/\A[a-z]{2,3}(-[A-Za-z0-9]{2,8})*\z/

  @primary_key false
  embedded_schema do
    field :schema, :integer
    field :key, :string
    field :title, :string
    field :locale, :string
    field :license, :string
    field :version, :string
    field :alignment, Ecto.Enum, values: [:strict, :warn]
  end

  @typedoc "The cast data of `pack.yaml`."
  @type t :: %__MODULE__{}

  @doc "Returns the format versions of `schema` that this release reads, currently `[1]`."
  @spec supported_schemas() :: [pos_integer()]
  def supported_schemas, do: @supported_schemas

  @doc """
  Casts the mapping of `pack.yaml` and returns a changeset whose errors
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(pack, attrs) do
    pack
    |> Cast.cast(attrs, required: [:schema, :key, :title, :locale, :license, :version])
    |> validate_schema(attrs)
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_regex(
      :locale,
      @locale_regex,
      "`locale` must be a language tag such as `en` or `de-DE`"
    )
    |> Cast.validate_max_length(:locale)
    |> validate_license()
    |> Cast.validate_max_length(:version)
  end

  defp validate_license(changeset) do
    case get_change(changeset, :license) do
      license when is_binary(license) ->
        if Spdx.expression?(license),
          do: changeset,
          else:
            Cast.add(
              changeset,
              :license,
              "`license` must be an SPDX license expression such as `CC0-1.0` or " <>
                "`MIT OR Apache-2.0`, with ids of SPDX License List #{Spdx.list_version()}"
            )

      _other ->
        changeset
    end
  end

  # A value of another type fails the cast, which leaves it out of the
  # changes, so the raw value comes from `attrs`. Its type error is replaced,
  # so that `schema` has one error, and that error names the supported
  # versions.
  defp validate_schema(changeset, %{"schema" => raw}) when not is_nil(raw) do
    version = get_change(changeset, :schema)

    cond do
      Cast.errored?(changeset, :schema) ->
        %{changeset | errors: Keyword.delete(changeset.errors, :schema)}
        |> unsupported(inspect(raw))

      version in @supported_schemas ->
        changeset

      true ->
        unsupported(changeset, Integer.to_string(version))
    end
  end

  defp validate_schema(changeset, _attrs), do: changeset

  defp unsupported(changeset, shown) do
    supported = Enum.map_join(@supported_schemas, ", ", &"`#{&1}`")

    Cast.add(
      changeset,
      :schema,
      "unsupported schema version `#{shown}`; supported versions: #{supported}"
    )
  end
end
