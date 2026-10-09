defmodule Espalier.Accounts.WebauthnCredential do
  @moduledoc """
  A passkey of a user: a discoverable WebAuthn credential registered with
  `wax_` (README section 6.6, `Espalier.Accounts.Passkeys`).

  The credential id is no secret; security events name a credential only by
  `credential_ref/1`. The COSE key is the public key of the credential.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @transports ~w(usb nfc ble smart-card hybrid internal)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webauthn_credentials" do
    field :credential_id, :binary
    field :cose_key, Espalier.Accounts.CoseKey
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :backup_eligible, :boolean, default: false
    field :backed_up, :boolean, default: false
    field :transports, {:array, :string}, default: []
    field :nickname, :string
    field :last_used_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc "The transport values that a credential stores."
  def transports, do: @transports

  @doc """
  Returns the first 8 hex characters of the SHA-256 hash of a credential id,
  the only form in which security events name a credential.
  """
  @spec credential_ref(binary()) :: String.t()
  def credential_ref(credential_id) when is_binary(credential_id) do
    :sha256 |> :crypto.hash(credential_id) |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  @doc false
  def changeset(webauthn_credential, attrs, user_scope) do
    webauthn_credential
    |> cast(attrs, [
      :credential_id,
      :cose_key,
      :sign_count,
      :aaguid,
      :backup_eligible,
      :backed_up,
      :transports,
      :nickname
    ])
    |> validate_required([:credential_id, :cose_key, :sign_count])
    |> validate_length(:nickname, max: 60, count: :codepoints)
    |> validate_subset(:transports, @transports)
    |> unique_constraint(:credential_id)
    |> put_change(:user_id, user_scope.user.id)
  end
end
