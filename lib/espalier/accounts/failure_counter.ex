defmodule Espalier.Accounts.FailureCounter do
  @moduledoc """
  Consecutive failures of one authenticator of one user
  (`Espalier.Accounts.FailureCounters`, README section 6.10).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "failure_counters" do
    field :authenticator, Ecto.Enum, values: [:password, :totp, :recovery_code, :passkey, :ldap]
    field :consecutive_failures, :integer, default: 0
    field :locked_until, :utc_datetime
    field :disabled_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(failure_counter, attrs, user_scope) do
    failure_counter
    |> cast(attrs, [:authenticator, :consecutive_failures, :locked_until, :disabled_at])
    |> validate_required([:authenticator, :consecutive_failures])
    |> put_change(:user_id, user_scope.user.id)
  end
end
