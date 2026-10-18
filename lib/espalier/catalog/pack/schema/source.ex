defmodule Espalier.Catalog.Pack.Schema.Source do
  @moduledoc """
  An entry of `sources.yaml`: a source that `cite` entries point to.

  `sources.yaml` sits in the pack directory and holds a list of entries. The file is optional. A `cite` entry of a block, a rule or an item has the form `source-key#locator` and names the `key` of one of these entries, for example `vendor-guide#Chapter 2`. The format requires the edition date and the retrieval date of every source. The order of the entries is free; the payload of the import sorts them by `key`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `key` | key | yes | The key format `^[a-z0-9][a-z0-9-]*$`, at most 255 characters. Unique in the file (checked across files). The part of a `cite` entry before `#` must equal a `key`. |
  | `title` | string | yes | The title of the source, at most 255 characters. |
  | `publisher` | string | yes | The publisher, at most 255 characters. |
  | `url` | string | no | An absolute URL with the scheme `http` or `https` and a host, at most 255 characters. |
  | `edition_date` | date in `YYYY-MM-DD` | yes | The date of the edition. A calendar date with a four-digit year and no sign; `2026-02-30` is an error. Quote it in YAML. |
  | `retrieved_on` | date in `YYYY-MM-DD` | yes | The date on which the source was read, with the same rules as `edition_date`. |
  | `kind` | one of `law`, `guidance`, `vendor`, `study`, `press`, `other` | yes | The type of the source. |

  Every string is not empty after trimming whitespace and holds no NUL character. A field that the table does not list is an error. A `null` value counts as absent.

  ## Example

  The file holds a list. The second entry omits the optional `url`.

  ```yaml
  - key: vendor-guide
    title: User guide of a writing assistant (invented example source)
    publisher: Example publisher (invented)
    url: https://example.org/writing-assistant-guide
    edition_date: "2026-03-01"
    retrieved_on: "2026-09-15"
    kind: vendor
  - key: office-study
    title: Interviews on writing assistants in office work (invented example source)
    publisher: Example institute (invented)
    edition_date: "2025-11-20"
    retrieved_on: "2026-09-15"
    kind: study
  ```

  ## Checks

    * "`sources.yaml` must hold a list of entries" when the file holds anything else, which includes an empty file.
    * "missing field `kind`" and "`kind` has no value" for a required field that is absent or `null`; the same for the other required fields.
    * "unknown field `name`" for a key that the table does not list.
    * "`key` value `Vendor Guide` does not match the key format `^[a-z0-9][a-z0-9-]*$`".
    * "`title` must have at most 255 characters", likewise for `publisher`, `url` and `key`.
    * "`url` must be an absolute `http` or `https` URL".
    * "`edition_date` must be a date in the form `YYYY-MM-DD`, got `2026-3-1`", likewise for `retrieved_on`.
    * "`kind` must be one of `law`, `guidance`, `vendor`, `study`, `press`, `other`".
    * Across files: "duplicate source key `vendor-guide`, first used in `sources.yaml` at line 1" and "unknown source `vendor-guide` in `cite`" for a `cite` entry whose part before `#` matches no `key`. A `cite` entry without the form `source-key#locator` fails in the file that holds it.

  ## See also

  [Content packs](content-packs.md), section "`sources.yaml`". The neighbor modules are `Espalier.Catalog.Pack.Schema.Block`, `Espalier.Catalog.Pack.Schema.Rule` and `Espalier.Catalog.Pack.Schema.Item`, whose `cite` lists name the keys, `Espalier.Catalog.Pack.Schema.GlossaryTerm` and `Espalier.Catalog.Pack.Validator` (the cross-file checks).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_change: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :key, :string
    field :title, :string
    field :publisher, :string
    field :url, :string
    field :edition_date, :string
    field :retrieved_on, :string
    field :kind, Ecto.Enum, values: [:law, :guidance, :vendor, :study, :press, :other]
  end

  @typedoc "The cast data of one entry of `sources.yaml`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `sources.yaml` and returns a changeset whose errors
  `Espalier.Catalog.Pack.Schema.Cast.errors/1` lists with their paths.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(source, attrs) do
    source
    |> Cast.cast(attrs, required: [:key, :title, :publisher, :edition_date, :retrieved_on, :kind])
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_max_length(:publisher)
    |> validate_url()
    |> Cast.validate_max_length(:url)
    |> Cast.validate_date(:edition_date)
    |> Cast.validate_date(:retrieved_on)
  end

  defp validate_url(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        if web_url?(url),
          do: changeset,
          else: Cast.add(changeset, :url, "`url` must be an absolute `http` or `https` URL")
    end
  end

  defp web_url?(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] ->
        is_binary(host) and host != ""

      _ ->
        false
    end
  end
end
