defmodule Espalier.Policies.ApprovedTool do
  @moduledoc """
  An entry of the approved tool list: a maintained table with status,
  conditions and review date (README section 7, domain rule 8). The table
  holds no person.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "approved_tools" do
    field :name, :string
    field :vendor, :string
    field :status, Ecto.Enum, values: [:approved, :restricted, :not_approved]
    field :conditions, :string
    field :reviewed_on, :date
    field :position, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(approved_tool, attrs) do
    approved_tool
    |> cast(attrs, [:name, :vendor, :status, :conditions, :reviewed_on, :position])
    |> validate_required([:name, :vendor, :status, :position])
    |> validate_length(:name, max: 255)
    |> validate_length(:vendor, max: 255)
    |> unique_constraint(:name)
  end
end
