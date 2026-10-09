defmodule Espalier.Accounts.TotpFactor do
  @moduledoc """
  The TOTP factor of a user (README section 6.6, `Espalier.Accounts.Totp`).

  The 20-byte secret is stored encrypted with the closure type, so a loaded
  value is `fn -> secret end`. A factor counts only with `enabled_at` set,
  which the first valid code sets. `last_used_step` holds the 30-second step
  of the last accepted code, so that each code works once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "totp_factors" do
    field :secret, Espalier.Encrypted.ClosureBinary, redact: true
    field :last_used_step, :integer
    field :enabled_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(totp_factor, attrs, user_scope) do
    totp_factor
    |> cast(attrs, [:last_used_step, :enabled_at])
    |> put_change(:user_id, user_scope.user.id)
  end
end
