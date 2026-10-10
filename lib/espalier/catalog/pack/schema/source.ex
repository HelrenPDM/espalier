defmodule Espalier.Catalog.Pack.Schema.Source do
  @moduledoc """
  An entry of `sources.yaml`: a source that `cite` entries point to, with
  `key`, `title`, `publisher`, an optional `url` (absolute, `http` or
  `https`), `edition_date` and `retrieved_on` (ISO 8601 dates in the form
  `YYYY-MM-DD`, README principle 4) and `kind`. `key`, `title`, `publisher`
  and `url` have at most 255 characters.
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

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `sources.yaml`."
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
