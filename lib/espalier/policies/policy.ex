defmodule Espalier.Policies.Policy do
  @moduledoc """
  A policy of the organization, such as the usage policy for AI
  assistants (README section 7, domain rule 8). Its text lives in numbered
  versions; the published version with the highest number is the current
  one. The table holds no person.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Policies.PolicyVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "policies" do
    field :key, :string
    field :title, :string

    has_many :versions, PolicyVersion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:key, :title])
    |> validate_required([:key, :title])
    |> validate_length(:key, max: 255)
    |> validate_format(:key, ~r/\A[a-z0-9][a-z0-9-]*\z/)
    |> validate_length(:title, max: 255)
    |> unique_constraint(:key)
  end
end
