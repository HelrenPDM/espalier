defmodule Espalier.Accounts.Passkeys do
  @moduledoc """
  Passkey registration and verification with `wax_` 0.7.0 and the checks of
  README section 6.6 (`Espalier.Accounts.Passkeys.Checks`, `ClientData`,
  `WaxCall`).

  Every ceremony uses attestation `"none"`, `user_verification: "required"`
  (the exact string, without which `wax_` skips the UV check), the
  configured `rp_id` and origins, and 300 seconds. The challenge comes from
  a row that `Espalier.Accounts.Challenges.consume/3` has already deleted;
  the struct is rebuilt from its bytes and never carries
  `allow_credentials`.

  Failures return `{:error, reason}` with an atom; controllers answer
  `authentication_failed` or `registration_failed` for every reason.
  """

  import Ecto.Query

  alias Espalier.Accounts

  alias Espalier.Accounts.{
    AuthChallenge,
    Challenges,
    FailureCounters,
    Scope,
    User,
    WebauthnCredential
  }

  alias Espalier.Accounts.Passkeys.{Checks, ClientData, Config, WaxCall}
  alias Espalier.Repo

  @timeout_seconds 300

  @doc "The options of `wax_` for a registration challenge."
  def registration_options(config \\ Config.get()) do
    [
      origin: config.origins,
      rp_id: config.rp_id,
      attestation: "none",
      user_verification: "required",
      timeout: @timeout_seconds
    ]
  end

  @doc "The options of `wax_` for an authentication challenge."
  def authentication_options(config \\ Config.get()) do
    [
      origin: config.origins,
      rp_id: config.rp_id,
      user_verification: "required",
      timeout: @timeout_seconds
    ]
  end

  @doc "A new registration challenge with random bytes."
  def new_registration_challenge(config \\ Config.get()),
    do: Wax.new_registration_challenge(registration_options(config))

  @doc "A new authentication challenge with random bytes."
  def new_authentication_challenge(config \\ Config.get()),
    do: Wax.new_authentication_challenge(authentication_options(config))

  @doc "Lists the passkeys of a user, oldest first."
  def list_credentials(%User{id: user_id}) do
    Repo.all(
      from c in WebauthnCredential,
        where: c.user_id == ^user_id,
        order_by: [c.inserted_at, c.id]
    )
  end

  @doc "Returns the passkey `id` of the scope's user, or `nil`."
  def get_credential(%Scope{user: %User{id: user_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get_by(WebauthnCredential, id: uuid, user_id: user_id)
      :error -> nil
    end
  end

  @doc "Deletes a passkey of the scope's user."
  def delete_credential(
        %Scope{user: %User{id: user_id}},
        %WebauthnCredential{user_id: user_id} = credential
      ) do
    Repo.delete(credential)
  end

  @doc """
  Verifies a RegistrationResponseJSON against the challenge row and stores
  the credential for the scope's user. `params` may carry `"nickname"`.

  Returns `{:ok, credential}` or `{:error, reason}`.
  """
  def register(%Scope{} = scope, %AuthChallenge{} = challenge_row, params, config \\ Config.get()) do
    with {:ok, raw_id} <- decode(params, ["rawId"]),
         {:ok, client_data_json} <- decode(params, ["response", "clientDataJSON"]),
         {:ok, attestation_object} <- decode(params, ["response", "attestationObject"]),
         :ok <- ClientData.check(client_data_json, :create, config.origins),
         challenge = rebuild(:registration, challenge_row, config),
         {:ok, {auth_data, _attestation}} <-
           WaxCall.run(fn -> Wax.register(attestation_object, client_data_json, challenge) end),
         credential_data = auth_data.attested_credential_data,
         :ok <- Checks.algorithm_allowed?(credential_data.credential_public_key),
         :ok <- Checks.backup_flags_valid?(auth_data),
         :ok <- same_id(raw_id, credential_data.credential_id) do
      insert_credential(scope, auth_data, params)
    end
    |> normalize_error()
  end

  defp insert_credential(scope, auth_data, params) do
    credential_data = auth_data.attested_credential_data

    attrs = %{
      credential_id: credential_data.credential_id,
      cose_key: credential_data.credential_public_key,
      sign_count: auth_data.sign_count,
      aaguid: Wax.AuthenticatorData.get_aaguid(auth_data),
      backup_eligible: auth_data.flag_backup_eligible,
      backed_up: auth_data.flag_credential_backed_up,
      transports: transports(get_in(params, ["response", "transports"])),
      nickname: nickname(params["nickname"])
    }

    case %WebauthnCredential{} |> WebauthnCredential.changeset(attrs, scope) |> Repo.insert() do
      {:ok, credential} ->
        {:ok, credential}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :credential_id),
          do: {:error, :credential_exists},
          else: {:error, :invalid_attributes}
    end
  end

  @doc """
  Verifies an AuthenticationResponseJSON against the challenge row.

  Without `expected_user` (discoverable sign-in), the `userHandle` must name
  the owner of the credential, and an owner with an external identity is
  refused. With `expected_user` (second factor and re-authentication), the
  owner must be that user.

  Returns `{:ok, %{user: user, credential: credential, risk_signal: nil |
  "sign_count"}}` or `{:error, reason}`.
  """
  def authenticate(
        %AuthChallenge{} = challenge_row,
        params,
        expected_user,
        config \\ Config.get()
      ) do
    with {:ok, assertion} <- decode_assertion(params),
         :ok <- ClientData.check(assertion.client_data_json, :get, config.origins),
         {:ok, {credential, owner}} <- fetch_credential(assertion.raw_id),
         :ok <- owner_matches(owner, expected_user),
         :ok <-
           Checks.user_handle_valid?(
             assertion.user_handle,
             owner.webauthn_user_handle,
             not is_nil(expected_user)
           ),
         :ok <- federated_owner(owner, expected_user),
         :ok <- usable(owner),
         {:ok, auth_data} <- wax_authenticate(credential, assertion, challenge_row, config),
         :ok <- Checks.backup_flags_valid?(auth_data) do
      record_use(credential, owner, auth_data)
    end
    |> normalize_error()
  end

  defp decode_assertion(params) do
    with {:ok, raw_id} <- decode(params, ["rawId"]),
         {:ok, client_data_json} <- decode(params, ["response", "clientDataJSON"]),
         {:ok, authenticator_data} <- decode(params, ["response", "authenticatorData"]),
         {:ok, signature} <- decode(params, ["response", "signature"]),
         {:ok, user_handle} <- decode_optional(params, ["response", "userHandle"]) do
      {:ok,
       %{
         raw_id: raw_id,
         client_data_json: client_data_json,
         authenticator_data: authenticator_data,
         signature: signature,
         user_handle: user_handle
       }}
    end
  end

  # The sixth argument is always the one resolved credential, because the
  # challenge carries no allow_credentials.
  defp wax_authenticate(credential, assertion, challenge_row, config) do
    challenge = rebuild(:authentication, challenge_row, config)

    WaxCall.run(fn ->
      Wax.authenticate(
        credential.credential_id,
        assertion.authenticator_data,
        assertion.signature,
        assertion.client_data_json,
        challenge,
        [{credential.credential_id, credential.cose_key}]
      )
    end)
  end

  defp owner_matches(_owner, nil), do: :ok
  defp owner_matches(%User{id: id}, %User{id: id}), do: :ok
  defp owner_matches(_owner, _expected_user), do: {:error, :credential_not_owned}

  defp federated_owner(owner, nil) do
    if Accounts.external_identity?(owner), do: {:error, :external_identity}, else: :ok
  end

  defp federated_owner(_owner, _expected_user), do: :ok

  defp usable(%User{status: :active} = user) do
    case FailureCounters.check(user, :passkey) do
      :ok -> :ok
      _locked_or_disabled -> {:error, :counter_locked}
    end
  end

  defp usable(%User{}), do: {:error, :user_disabled}

  defp record_use(credential, owner, auth_data) do
    risk = Checks.sign_count(credential.sign_count, auth_data.sign_count)
    now = DateTime.utc_now(:second)

    Repo.update_all(
      from(c in WebauthnCredential,
        where: c.id == ^credential.id,
        update: [
          set: [
            sign_count: fragment("GREATEST(?, ?)", c.sign_count, ^auth_data.sign_count),
            backed_up: ^auth_data.flag_credential_backed_up,
            last_used_at: ^now
          ]
        ]
      ),
      []
    )

    {:ok,
     %{
       user: owner,
       credential: credential,
       risk_signal: if(risk == :risk, do: "sign_count")
     }}
  end

  defp fetch_credential(raw_id) do
    query =
      from c in WebauthnCredential,
        where: c.credential_id == ^raw_id,
        join: u in User,
        on: u.id == c.user_id,
        select: {c, u}

    case Repo.one(query) do
      nil -> {:error, :unknown_credential}
      found -> {:ok, found}
    end
  end

  # Rebuilds the challenge from the stored bytes. Wax.Challenge.new/1 always
  # sets issued_at to now, so the override aligns the expiry check of wax_
  # with the row.
  defp rebuild(type, challenge_row, config) do
    challenge =
      case type do
        :registration ->
          Wax.new_registration_challenge(
            registration_options(config) ++ [bytes: challenge_row.challenge]
          )

        :authentication ->
          Wax.new_authentication_challenge(
            authentication_options(config) ++ [bytes: challenge_row.challenge]
          )
      end

    %{challenge | issued_at: Challenges.issued_at(challenge_row)}
  end

  defp same_id(raw_id, credential_id) do
    if raw_id == credential_id, do: :ok, else: {:error, :credential_id_mismatch}
  end

  defp decode(params, path) do
    case get(params, path) do
      value when is_binary(value) ->
        case Base.url_decode64(value, padding: false) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :malformed_response}
        end

      _ ->
        {:error, :malformed_response}
    end
  end

  defp decode_optional(params, path) do
    case get(params, path) do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      _value -> decode(params, path)
    end
  end

  defp get(params, path) when is_map(params) do
    Enum.reduce_while(path, params, fn key, acc ->
      case acc do
        %{^key => value} -> {:cont, value}
        _ -> {:halt, nil}
      end
    end)
  end

  defp get(_params, _path), do: nil

  defp transports(list) when is_list(list) do
    list |> Enum.filter(&(&1 in WebauthnCredential.transports())) |> Enum.uniq()
  end

  defp transports(_value), do: []

  defp nickname(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      name -> name
    end
  end

  defp nickname(_value), do: nil

  # Wax returns exception structs; the reason of the event log is an atom.
  defp normalize_error({:error, %Wax.InvalidClientDataError{reason: reason}}),
    do: {:error, reason}

  defp normalize_error({:error, %{__exception__: true} = error}), do: {:error, reason(error)}

  defp normalize_error(result), do: result

  defp reason(%Wax.ExpiredChallengeError{}), do: :challenge_expired
  defp reason(%Wax.InvalidSignatureError{}), do: :invalid_signature
  defp reason(%Wax.AttestationVerificationError{reason: reason}) when is_atom(reason), do: reason
  defp reason(%Wax.UnsupportedSignatureAlgorithmError{}), do: :algorithm_not_allowed
  defp reason(%Wax.InvalidAuthenticatorDataError{}), do: :invalid_authenticator_data
  defp reason(%Wax.InvalidCBORError{}), do: :invalid_cbor
  defp reason(_error), do: :invalid_response
end
