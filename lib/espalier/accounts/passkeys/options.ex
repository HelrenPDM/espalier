defmodule Espalier.Accounts.Passkeys.Options do
  @moduledoc """
  The options JSON of the passkey ceremonies, as `@simplewebauthn/browser`
  passes it to `navigator.credentials` (README section 6.6). Every binary is
  base64url without padding. Credentials are discoverable and need user
  verification, attestation is `"none"`, and the timeout is 300 seconds.
  """

  alias Espalier.Accounts.Passkeys.Config
  alias Espalier.Accounts.{User, WebauthnCredential}

  # Algorithms that wax_ verifies: EdDSA, ES256 and RS256 (decision D13).
  @algorithms [-8, -7, -257]
  @timeout_ms 300_000

  @doc "The COSE algorithms offered at registration."
  def algorithms, do: @algorithms

  @doc """
  Returns the creation options for `user`, whose `webauthn_user_handle` is
  set, with every credential of the user in `excludeCredentials`.
  """
  def creation(%User{} = user, %Wax.Challenge{bytes: bytes}, credentials, config \\ Config.get()) do
    %{
      "rp" => %{"id" => config.rp_id, "name" => config.rp_name},
      "user" => %{
        "id" => encode(user.webauthn_user_handle),
        "name" => user.email || user.display_name,
        "displayName" => user.display_name || user.email
      },
      "challenge" => encode(bytes),
      "pubKeyCredParams" => Enum.map(@algorithms, &%{"type" => "public-key", "alg" => &1}),
      "timeout" => @timeout_ms,
      "excludeCredentials" => Enum.map(credentials, &descriptor/1),
      "authenticatorSelection" => %{
        "residentKey" => "required",
        "userVerification" => "required"
      },
      "attestation" => "none"
    }
  end

  @doc """
  Returns the request options. `allowCredentials` appears only for a
  non-empty list (second factor and re-authentication); the sign-in request
  carries none, which conditional UI needs.
  """
  def request(%Wax.Challenge{bytes: bytes}, allow, config \\ Config.get()) do
    options = %{
      "challenge" => encode(bytes),
      "timeout" => @timeout_ms,
      "rpId" => config.rp_id,
      "userVerification" => "required"
    }

    case allow do
      [_ | _] -> Map.put(options, "allowCredentials", Enum.map(allow, &descriptor/1))
      _ -> options
    end
  end

  defp descriptor(%WebauthnCredential{} = credential) do
    %{
      "type" => "public-key",
      "id" => encode(credential.credential_id),
      "transports" => credential.transports || []
    }
  end

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)
end
