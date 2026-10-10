defmodule Espalier.Catalog.Station do
  @moduledoc """
  A station of the learner journey. `config` holds the station texts of the
  pack: the self-assessment `question`, the `intro` of the overview,
  credential and companion format stations, and the `intro` and `questions`
  of `feedback.yaml` for the feedback station.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "stations" do
    field :position, :integer

    field :kind, Ecto.Enum,
      values: [:self_assessment, :overview, :module, :credential, :companion_formats, :feedback]

    field :title, :string
    field :config, :map, default: %{}

    belongs_to :program, Program
    belongs_to :module, CatalogModule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(station, attrs) do
    station
    |> cast(attrs, [:position, :kind, :title, :config])
    |> validate_required([:position, :kind, :title])
  end
end
