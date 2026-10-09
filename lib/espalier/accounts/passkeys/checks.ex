defmodule Espalier.Accounts.Passkeys.Checks do
  @moduledoc """
  The checks that `wax_` 0.7.0 leaves to the application (README section
  6.6): the COSE algorithm allowlist (`wax_` issue #59), the backup flags
  (issue #60), the owner of the user handle and the sign count.
  """

  alias Espalier.Accounts.Passkeys.Options

  @doc """
  Returns `:ok` when the COSE algorithm (key `3`) is -7, -8 or -257, and
  `{:error, :algorithm_not_allowed}` otherwise.
  """
  @spec algorithm_allowed?(map()) :: :ok | {:error, :algorithm_not_allowed}
  def algorithm_allowed?(cose_key) when is_map(cose_key) do
    if Map.get(cose_key, 3) in Options.algorithms(),
      do: :ok,
      else: {:error, :algorithm_not_allowed}
  end

  def algorithm_allowed?(_cose_key), do: {:error, :algorithm_not_allowed}

  @doc """
  Rejects authenticator data with the backup state set and backup
  eligibility unset. Synced passkeys set both flags and pass.
  """
  @spec backup_flags_valid?(Wax.AuthenticatorData.t()) :: :ok | {:error, :backup_state_invalid}
  def backup_flags_valid?(%Wax.AuthenticatorData{} = auth_data) do
    if auth_data.flag_credential_backed_up and not auth_data.flag_backup_eligible,
      do: {:error, :backup_state_invalid},
      else: :ok
  end

  @doc """
  Checks the `userHandle` of an assertion against the handle of the owner.
  A discoverable sign-in (`expected_user?` false) requires the handle; with
  an expected user, a present handle must match.
  """
  @spec user_handle_valid?(binary() | nil, binary() | nil, boolean()) ::
          :ok | {:error, :user_handle_mismatch | :user_handle_missing}
  def user_handle_valid?(nil, _owner_handle, false), do: {:error, :user_handle_missing}
  def user_handle_valid?(nil, _owner_handle, true), do: :ok

  def user_handle_valid?(handle, owner_handle, _expected_user?)
      when is_binary(handle) and is_binary(owner_handle) do
    if Plug.Crypto.secure_compare(handle, owner_handle),
      do: :ok,
      else: {:error, :user_handle_mismatch}
  end

  def user_handle_valid?(_handle, _owner_handle, _expected_user?),
    do: {:error, :user_handle_mismatch}

  @doc """
  Returns `:risk` when the stored or the new count is nonzero and the new
  count is not greater than the stored one, and `:ok` otherwise. A risk
  does not fail the sign-in; it is logged as `risk_signal`.
  """
  @spec sign_count(non_neg_integer(), non_neg_integer()) :: :ok | :risk
  def sign_count(stored, new) do
    if (stored != 0 or new != 0) and new <= stored, do: :risk, else: :ok
  end
end
