defmodule Espalier.Catalog.Requirement do
  @moduledoc """
  A requirement of a qualification. `target_key` holds the module number, the
  assessment key, the policy key, the format key or the qualification code,
  as a string.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Qualification

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "requirements" do
    field :kind, Ecto.Enum,
      values: [
        :module_completed,
        :assessment_passed,
        :policy_acknowledged,
        :attendance,
        :qualification_held
      ]

    field :target_key, :string

    belongs_to :qualification, Qualification

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, [:kind, :target_key])
    |> validate_required([:kind, :target_key])
  end
end
