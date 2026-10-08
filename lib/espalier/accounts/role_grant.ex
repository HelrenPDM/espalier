defmodule Espalier.Accounts.RoleGrant do
  @moduledoc """
  A role of a user beyond `learner`. Grants with source `manual` come from an
  admin or a release function; grants with source `idp_claim` are replaced at
  every federated sign-in (README section 6.11).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "role_grants" do
    field :role, Ecto.Enum,
      values: [:learner, :facilitator, :author, :registrar, :analyst, :admin]

    field :source, Ecto.Enum, values: [:idp_claim, :manual]
    field :provider_key, :string
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(role_grant, attrs, user_scope) do
    role_grant
    |> cast(attrs, [:role, :source, :provider_key])
    |> validate_required([:role, :source])
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:user_id, :role, :source])
  end
end
