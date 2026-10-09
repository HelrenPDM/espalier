defmodule Espalier.Accounts.FailureCounter do
  @moduledoc """
  Consecutive failures of one authenticator of one user
  (`Espalier.Accounts.FailureCounters`, README section 6.10).

  Rows of the authenticator `ldap` (task 0007) carry `provider_key` and
  `subject_hash` and no `user_id`, so the count of a directory account
  exists before its platform account does. `subject_hash` takes the input
  of `Espalier.Accounts.ExternalIdentity.hash_input/3`, so the counter and
  the identity of a directory account carry the same value.
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
    field :provider_key, :string
    field :subject_hash, Espalier.Hashed.HMAC, redact: true
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
