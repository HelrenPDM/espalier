defmodule Espalier.Accounts.ExternalIdentity do
  @moduledoc """
  An identity at an external provider, keyed by `provider_key` and
  `subject_hash` (README section 6.2, rule 3). Accounts are never created or
  linked through an e-mail address.

  A directory identity (task 0007) has the issuer `"ldap:" <> provider_key`,
  no tenant, the `objectGUID` or `entryUUID` as subject, and the encrypted
  directory attributes `directory_dn`, `directory_upn` and
  `directory_login`.

  `subject_hash` holds the keyed hash of `hash_input/3`, so the same subject
  at two issuers yields two keys. The changeset fills it; a caller never
  passes it. A lookup passes `hash_input/3` as the value of `subject_hash`,
  and the field type hashes it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "external_identities" do
    field :provider_key, :string
    field :issuer, :string
    field :tenant_id, :string
    field :subject, Espalier.Encrypted.Binary, redact: true
    field :subject_hash, Espalier.Hashed.HMAC, redact: true
    # Directory attributes of an LDAP identity (task 0007), refreshed at
    # every directory sign-in; nil for OIDC identities.
    field :directory_dn, Espalier.Encrypted.Binary, redact: true
    field :directory_upn, Espalier.Encrypted.Binary, redact: true
    field :directory_login, Espalier.Encrypted.Binary, redact: true
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the input of `subject_hash`: issuer, tenant id and subject, joined by NUL bytes."
  @spec hash_input(String.t(), String.t() | nil, String.t()) :: String.t()
  def hash_input(issuer, tenant_id, subject) do
    Enum.join([issuer, tenant_id || "", subject], <<0>>)
  end

  @doc false
  def changeset(external_identity, attrs, user_scope) do
    external_identity
    |> cast(attrs, [
      :provider_key,
      :issuer,
      :tenant_id,
      :subject,
      :directory_dn,
      :directory_upn,
      :directory_login
    ])
    |> put_subject_hash()
    |> validate_required([:provider_key, :issuer, :subject, :subject_hash])
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:user_id, :provider_key])
    |> unique_constraint([:provider_key, :subject_hash])
  end

  defp put_subject_hash(changeset) do
    issuer = get_field(changeset, :issuer)
    subject = get_field(changeset, :subject)

    if is_binary(issuer) and is_binary(subject) do
      put_change(
        changeset,
        :subject_hash,
        hash_input(issuer, get_field(changeset, :tenant_id), subject)
      )
    else
      changeset
    end
  end
end
