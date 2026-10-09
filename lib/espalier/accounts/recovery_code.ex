defmodule Espalier.Accounts.RecoveryCode do
  @moduledoc """
  One recovery code of a user, stored as HMAC-SHA256 with a server key
  (README section 6.6, `Espalier.Accounts.RecoveryCodes`). `used_at` marks a
  used code.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recovery_codes" do
    field :code_hmac, :binary, redact: true
    field :used_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recovery_code, attrs, user_scope) do
    recovery_code
    |> cast(attrs, [:code_hmac, :used_at])
    |> validate_required([:code_hmac])
    |> put_change(:user_id, user_scope.user.id)
  end
end
