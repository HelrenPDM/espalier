defmodule Espalier.Catalog.Source do
  @moduledoc "A source that citations point to, with edition date and retrieval date."
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sources" do
    field :key, :string
    field :title, :string
    field :publisher, :string
    field :url, :string
    field :edition_date, :date
    field :retrieved_on, :date
    field :kind, Ecto.Enum, values: [:law, :guidance, :vendor, :study, :press, :other]
    field :archived_at, :utc_datetime

    belongs_to :program, Program

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:key, :title, :publisher, :url, :edition_date, :retrieved_on, :kind])
    |> validate_required([:key, :title, :publisher, :edition_date, :retrieved_on, :kind])
  end
end
