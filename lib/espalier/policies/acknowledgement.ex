defmodule Espalier.Policies.Acknowledgement do
  @moduledoc """
  The acknowledgement of a published policy version by a user (README
  principle 1). The row belongs to the person in `user_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Policies.PolicyVersion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "acknowledgements" do
    field :acknowledged_at, :utc_datetime
    belongs_to :policy_version, PolicyVersion
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Checks a row whose values `Espalier.Policies` has set on the struct. The
  changeset casts nothing, so no member can come from a request; it puts
  `user_id` from the scope and declares the unique constraint.
  """
  def changeset(%__MODULE__{} = acknowledgement, user_scope) do
    acknowledgement
    |> change(user_id: user_scope.user.id)
    |> validate_required([:policy_version_id, :acknowledged_at])
    |> unique_constraint([:user_id, :policy_version_id])
  end
end
