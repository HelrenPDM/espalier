defmodule Espalier.Credentials.Credential do
  @moduledoc """
  A credential of a user for a qualification, in one of the states of
  `credential-lifecycle.puml`. `unlocks_snapshot` keeps the tasks that
  `Qualification.unlocks` named at issue time (README principle 2), and
  `refresh_due_at` records when the credential last entered `refresh_due`.
  The row carries no score and no rank, and it belongs to the person in
  `user_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Qualification

  @statuses [:active, :refresh_due, :expired, :revoked]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :status, Ecto.Enum, values: @statuses
    field :issued_at, :utc_datetime
    field :valid_until, :date
    field :refresh_due_at, :utc_datetime
    field :unlocks_snapshot, {:array, :string}, default: []
    belongs_to :qualification, Qualification
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc "The statuses in which a credential is in force."
  def in_force_statuses, do: [:active, :refresh_due]

  @doc """
  Checks a row whose values `Espalier.Credentials` has set on the struct.
  The changeset casts nothing, so no member can come from a request; it puts
  `user_id` from the scope and declares the unique constraint.
  """
  def changeset(%__MODULE__{} = credential, user_scope) do
    credential
    |> change(user_id: user_scope.user.id)
    |> validate_required([:qualification_id, :status, :issued_at])
    |> unique_constraint([:user_id, :qualification_id])
  end
end
