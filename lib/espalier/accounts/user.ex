# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Accounts.User do
  @moduledoc """
  A user account. E-mail address, display name and org unit are encrypted;
  lookups by address go through `email_hash` (README section 6.9).

  This is the only module in `lib/` that calls `Argon2.hash_pwd_salt/1` and
  `Argon2.verify_pass/2`. Every password passes `PasswordPolicy.prepare/1`
  (Unicode NFC, decision D12) before it is checked, hashed or verified.
  """
  use Ecto.Schema
  import Ecto.Changeset

  require Logger

  alias Espalier.Accounts.{
    ExternalIdentity,
    FailureCounter,
    PasswordPolicy,
    RecoveryCode,
    RoleGrant,
    TotpFactor,
    UserToken,
    WebauthnCredential
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, Espalier.Encrypted.Binary, redact: true
    field :email_hash, Espalier.Hashed.HMAC, redact: true
    field :display_name, Espalier.Encrypted.Binary, redact: true
    field :org_unit, Espalier.Encrypted.Binary, redact: true
    field :locale, :string, default: "en"
    field :status, Ecto.Enum, values: [:active, :disabled], default: :active
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :last_login_at, :utc_datetime
    # 64 random bytes, the WebAuthn user.id; no personal data (task 0005).
    field :webauthn_user_handle, :binary, redact: true

    has_many :tokens, UserToken
    has_many :role_grants, RoleGrant
    has_many :external_identities, ExternalIdentity
    has_many :failure_counters, FailureCounter
    has_many :webauthn_credentials, WebauthnCredential
    has_one :totp_factor, TotpFactor
    has_many :recovery_codes, RecoveryCode

    timestamps(type: :utc_datetime)
  end

  @doc """
  Normalizes an e-mail address for storage and lookup: trimmed and
  lower-cased, because the keyed hash is case-sensitive.
  """
  @spec normalize_email(String.t()) :: String.t()
  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  @doc """
  Returns the local part of a normalized address, the display name of an
  account that is created from an address alone.
  """
  @spec local_part(String.t()) :: String.t()
  def local_part(email) when is_binary(email) do
    email |> normalize_email() |> String.split("@", parts: 2) |> hd()
  end

  @doc """
  Changeset for an invited local user. Requires `email`; a missing or blank
  `display_name` becomes the local part of the address.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :display_name, :locale])
    |> validate_email()
    |> put_default_display_name()
    |> validate_display_name()
    |> validate_locale()
  end

  @doc """
  Changeset for a user without an address, such as a demo user.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :locale, :org_unit])
    |> validate_required([:display_name])
    |> validate_display_name()
    |> validate_locale()
  end

  @doc """
  Changeset for an account that a provider sign-in creates (task 0006): an
  optional verified address and the display name of the provider, else the
  local part of the address, else `User`.
  """
  def external_changeset(user, attrs) do
    changeset =
      user
      |> cast(attrs, [:email, :display_name])
      |> put_default_display_name()

    changeset =
      if get_change(changeset, :email), do: validate_email(changeset), else: changeset

    changeset
    |> put_fallback_display_name()
    |> validate_required([:display_name])
    |> validate_display_name()
  end

  defp put_fallback_display_name(changeset) do
    if get_field(changeset, :display_name) in [nil, ""],
      do: put_change(changeset, :display_name, "User"),
      else: changeset
  end

  @doc """
  Changeset that sets a confirmed new address, from the e-mail change token.
  """
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> put_email_hash()
    |> unsafe_validate_unique(:email_hash, Espalier.Repo, error_key: :email)
    |> unique_constraint(:email, name: :users_email_hash_index)
  end

  # The HMAC type hashes the normalized plaintext on dump.
  defp put_email_hash(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email_hash, email)
    end
  end

  defp put_default_display_name(changeset) do
    with name when name in [nil, ""] <- changeset |> get_field(:display_name) |> trim(),
         email when is_binary(email) <- get_field(changeset, :email) do
      put_change(changeset, :display_name, local_part(email))
    else
      _ -> update_change(changeset, :display_name, &trim/1)
    end
  end

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)

  defp validate_display_name(changeset) do
    validate_length(changeset, :display_name, min: 1, max: 200, count: :codepoints)
  end

  defp validate_locale(changeset) do
    validate_format(changeset, :locale, ~r/\A[a-z]{2}(-[A-Z]{2})?\z/)
  end

  @doc """
  A user changeset for setting or changing the password.

  The password is normalized to NFC first, then checked by
  `PasswordPolicy.validate/2` and hashed with Argon2id.

  ## Options

    * `:hash_password` - hashes the password and clears the virtual field.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> update_change(:password, &PasswordPolicy.prepare/1)
    |> validate_required([:password])
    |> PasswordPolicy.validate(user)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password after NFC normalization.

  If there is no user or the user doesn't have a password, we call
  `Argon2.no_user_verify/0` to avoid timing attacks. A stored value that is
  no Argon2 hash, and an error of the native code, count as a failed
  verification and are logged without the input.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and is_binary(password) and byte_size(password) > 0 do
    Argon2.verify_pass(PasswordPolicy.prepare(password), hashed_password)
  rescue
    error in ArgumentError ->
      Logger.error("password verification failed: #{Exception.message(error)}")
      false
  end

  def valid_password?(_, _) do
    no_user_verify()
    false
  end

  @doc """
  Runs a dummy verification, so an unknown account takes as long as a known
  one.
  """
  @spec no_user_verify() :: false
  def no_user_verify do
    Argon2.no_user_verify()
    false
  end
end
