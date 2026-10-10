defmodule Espalier.Catalog.Qualification do
  @moduledoc """
  A qualification with its requirements. `unlocks` lists the tasks that a
  credential for it permits; the model holds no rank, score or level.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Program, Requirement}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "qualifications" do
    field :code, :string
    field :title, :string
    field :audience, :string
    field :unlocks, {:array, :string}, default: []
    field :add_on, :boolean, default: false
    field :validity_kind, Ecto.Enum, values: [:none, :months, :event]
    field :validity_months, :integer
    field :refresher_mode, Ecto.Enum, values: [:update_unit, :full_run, :test_only]

    field :phases, {:array, Ecto.Enum},
      values: [:orient, :understand, :apply, :anchor, :update],
      default: []

    field :archived_at, :utc_datetime

    belongs_to :program, Program
    has_many :requirements, Requirement

    many_to_many :prerequisites, __MODULE__,
      join_through: "qualification_prerequisites",
      join_keys: [qualification_id: :id, prerequisite_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(qualification, attrs) do
    qualification
    |> cast(attrs, [
      :code,
      :title,
      :audience,
      :unlocks,
      :add_on,
      :validity_kind,
      :validity_months,
      :refresher_mode,
      :phases
    ])
    |> validate_required([:code, :title, :audience, :add_on, :validity_kind])
  end
end
