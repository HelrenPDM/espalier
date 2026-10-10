defmodule Espalier.Catalog.Pack.Schema.Pack do
  @moduledoc """
  The schema of `pack.yaml`: `schema` (the format version, 1), `key` (becomes
  `programs.slug`), `title`, `locale` (a language tag), `license` (an SPDX
  license identifier or expression), `version` (becomes
  `programs.pack_version`) and the optional `alignment` (`strict` or `warn`,
  default `strict`), which decides whether checks 1 to 3 of
  `Espalier.Catalog.Alignment` report errors or warnings.

  Any `schema` value other than a supported version, also a value that is
  no integer such as `"1"`, is an error whose message names the supported
  versions. `key`, `title`, `locale` and `version` land in `varchar(255)`
  columns and have at most 255 characters.
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @supported_schemas [1]
  @locale_regex ~r/\A[a-z]{2,3}(-[A-Za-z0-9]{2,8})*\z/
  @license_regex ~r/\A[A-Za-z0-9][A-Za-z0-9.+-]*( (AND|OR|WITH) [A-Za-z0-9][A-Za-z0-9.+-]*)*\z/

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

  @type t :: %__MODULE__{}

  @doc "The schema versions of the pack format that this release reads."
  @spec supported_schemas() :: [pos_integer()]
  def supported_schemas, do: @supported_schemas

  @doc "Casts the data of `pack.yaml`."
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
    |> Cast.validate_regex(
      :license,
      @license_regex,
      "`license` must be an SPDX license identifier or expression such as `CC0-1.0`"
    )
    |> Cast.validate_max_length(:version)
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
